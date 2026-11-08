"""New thunder rolls learned from a storm recording. For each thunder event: each band's slow swell and fade
(above the rain), plus its inner flicker. New rolls reuse those measurements with a new flicker (IAAFT),
new noise, a random stretch, level and side. No audio from the recording is kept."""
import sys, os, numpy as np, soundfile as sf
from scipy.signal import hilbert, resample
from scipy.ndimage import uniform_filter1d
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__))); import texture as T
x, sr = sf.read(sys.argv[1], dtype='float32'); K = 32; hop = 441  # 10 ms
n = len(x) - len(x) % (2 * hop); x = x[:n]; H, cf = T.filterbank(n, sr, K, lo=20); C = 2; F = n // hop
P = np.zeros((C, K, F), np.float32)
for c in range(C):
    X = np.fft.rfft(x[:, c])
    for k in range(K): P[c, k] = (np.abs(hilbert(np.fft.irfft(X * H[k], n))) ** 2).reshape(F, hop).mean(1)
    del X
rain = np.median(P[:, :, 13500:16500], axis=2, keepdims=True)                 # rain-only stretch, 135-165 s
low = 10 * np.log10(P[:, cf < 400].sum((0, 1)) / rain[:, cf < 400].sum() + 1e-12); low = uniform_filter1d(low, 100)
on = low > 4; events = []; i = 0
while i < F:
    if on[i]:
        j = i
        while j < F and on[j]: j += 1
        if j - i > 1000: events.append((max(0, i - 100), min(F, j + 200)))
        i = j
    i += 1
print('events (s)', [(a / 100, b / 100) for a, b in events])
out_dir = sys.argv[2]; os.makedirs(out_dir, exist_ok=True); rng = np.random.default_rng(5); made = []
for e, (a, b) in enumerate(events):
    ex = np.clip(P[:, :, a:b] - rain * 1.2, 0, None)                         # thunder above the rain
    slow = uniform_filter1d(ex, 30, axis=2)                                    # 300 ms swell and fade
    flick = np.clip(np.sqrt(ex / (slow + 1e-3 * slow.max(axis=2, keepdims=True) + 1e-12)), 0, 2.5).reshape(C * K, -1)  # quiet bands don't blow up                   # inner flicker, level removed
    for v in range(2):
        stretch = rng.uniform(.8, 1.25); L = int((b - a) * stretch)
        sl = np.clip(resample(slow.reshape(C * K, -1), L, axis=1), 0, None).reshape(C, K, L)
        if rng.random() < .5: sl = sl[::-1]                                    # mirror left and right
        fl = T.iaaft(np.nan_to_num(flick), 20, rng, end_spectral=False); fl = resample(fl, L, axis=1).reshape(C, K, L)
        keep = np.clip((slow.max(axis=2) / (rain[:, :, 0] + 1e-12) - 1.5) / 3, 0, 1)       # only bands where the thunder clearly beats the rain
        env = np.sqrt(sl) * np.clip(fl, 0, 2.5) * keep[:, :, None]; print('  bands kept', int((keep.mean(0) > .5).sum()), 'top kept Hz', int(cf[np.where(keep.mean(0) > .1)[0].max()]) if (keep.mean(0) > .1).any() else 0); m = L * hop; m -= m % 2
        Hm, _ = T.filterbank(m, sr, K, lo=20); y = np.zeros((m, C), np.float32)
        for c in range(C):
            E = np.stack([np.interp(np.arange(m) / hop, np.arange(L), e) for e in env[c]])  # linear, so no ringing between frames
            car = T.unit(T.bands(rng.standard_normal(m), Hm))
            y[:, c] = T.combine(np.clip(E, 0, None) * car, Hm)
        fade = np.minimum(1, np.minimum(np.arange(m), m - np.arange(m)) / (.5 * sr))[:, None]; y *= fade
        level = rng.uniform(.6, 1); y *= level
        name = f'{out_dir}/thunder{len(made) + 1}.wav'; sf.write(name, y, sr, subtype='FLOAT'); made.append(name)
        pk = np.abs(y).max(); print(name, 'length s', round(m / sr, 1), 'peak', round(float(pk), 2), 'from event', e + 1, 'stretch', round(stretch, 2))
