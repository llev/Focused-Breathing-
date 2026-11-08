"""Trace a bird recording into note contours (pitch and loudness over time), grouped into phrases.
Only the contours are kept; the page sings them with oscillators."""
import sys, json, numpy as np, soundfile as sf
from scipy.signal import stft
x, sr = sf.read(sys.argv[1], dtype='float32'); m = x.mean(1)
hop = 128; f, t, Z = stft(m, sr, nperseg=1024, noverlap=1024 - hop); S = np.abs(Z)
band = (f > 1700) & (f < 9000); fb = f[band]; Sb = S[band]
floor = np.median(Sb, axis=1, keepdims=True)                     # each frequency's background level
snr = 20 * np.log10(Sb / (floor + 1e-12) + 1e-12)
k = np.argmax(snr, axis=0); best = snr[k, np.arange(len(t))]
# parabolic interpolation for a finer pitch
a = np.log(Sb[np.clip(k - 1, 0, len(fb) - 1), np.arange(len(t))] + 1e-12); b = np.log(Sb[k, np.arange(len(t))] + 1e-12); c = np.log(Sb[np.clip(k + 1, 0, len(fb) - 1), np.arange(len(t))] + 1e-12)
off = np.clip(.5 * (a - c) / (a - 2 * b + c + 1e-12), -.5, .5); freq = fb[k] + off * (f[1] - f[0])
on = best > float(sys.argv[3]) if len(sys.argv) > 3 else best > 22
notes = []; i = 0; dt = hop / sr
while i < len(t):
    if not on[i]: i += 1; continue
    j = i
    while j + 1 < len(t) and on[j + 1] and abs(np.log2(freq[j + 1] / freq[j])) < .25: j += 1
    if j - i >= 4:
        fr = freq[i:j + 1]; am = best[i:j + 1]
        dur = (j - i + 1) * dt; spread = np.ptp(np.log2(fr))
        if not (dur > .6 and spread < .05):                          # skip steady machine tones
            cols = np.arange(i, j + 1); lv = []
            for h in (1, 2, 3):
                idx = np.clip(np.round(fr * h / (f[1] - f[0])).astype(int), 0, len(f) - 1)
                lv.append(np.mean(S[idx, cols]))
            harm = [round(float(min(1.5, lv[1] / lv[0])), 2), round(float(min(1.5, lv[2] / lv[0])), 2)]
            notes.append(dict(t=float(t[i]), f=[round(float(v)) for v in fr[::2]], a=[round(float(v), 1) for v in am[::2]], h=harm))
    i = j + 1
phrases = []; cur = []
for n in notes:
    if cur and n['t'] - (cur[-1]['t'] + len(cur[-1]['f']) * 2 * dt) > .35: phrases.append(cur); cur = []
    cur.append(n)
if cur: phrases.append(cur)
out = []
for p in phrases:
    t0 = p[0]['t']; out.append([[round(n['t'] - t0, 3), n['f'], n['a'], n['h']] for n in p])
gaps = [phrases[i + 1][0]['t'] - (phrases[i][-1]['t'] + len(phrases[i][-1]['f']) * 2 * dt) for i in range(len(phrases) - 1)]
json.dump(notes, open(sys.argv[2] + '.notes', 'w'))
json.dump(dict(dt=round(dt * 2, 5), phrases=out, gaps=[round(g, 2) for g in gaps]), open(sys.argv[2], 'w'), separators=(',', ':'))
lens = [len(p) for p in phrases]
print('notes', len(notes), 'phrases', len(phrases), 'notes/phrase median', np.median(lens), 'gap median s', round(float(np.median(gaps)), 2),
      'pitch range Hz', int(min(min(n['f']) for n in notes)), int(max(max(n['f']) for n in notes)))
