"""Build the storm's rain as three seamless loops: glass taps, metal taps and outside rain.
Taps are new noise bursts, each given the spectrum, stereo balance and decay of a measured tap, with a sharp
attack and minimum-phase shaping so the start stays crisp. Outside rain is texture synthesis of the tap-free recording."""
import sys, os, numpy as np, soundfile as sf
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__))); import texture as T
from scipy.ndimage import uniform_filter1d
sr = 44100; SEC = 20; n = SEC * sr; rng = np.random.default_rng(11)
Z = np.load('taps.npz'); P = Z['patches'].astype(np.float32); cent = Z['cent']; rate_all = float(Z['rate']); seconds = len(cent) / rate_all
f512 = np.fft.rfftfreq(512, 1 / sr); NF = 2048; fN = np.fft.rfftfreq(NF, 1 / sr)
def minphase(mag):  # minimum-phase spectrum with this magnitude, via the real cepstrum
    c = np.fft.irfft(np.log(np.maximum(mag, 1e-6)), NF); w = np.zeros(NF); w[0] = 1; w[1:NF // 2] = 2; w[NF // 2] = 1
    return np.exp(np.fft.rfft(c * w, NF))
typical = None
def layer(idx, label, density=1.0, rough=(.05, .3), ring=.0006, cap=None):
    global typical; typical = np.median((P[idx] ** 2).sum((1, 2, 3)))
    out = np.zeros((n + NF, 2), np.float32); count = rng.poisson(len(idx) / seconds * SEC * density)
    t = np.arange(NF) / sr
    for _ in range(count):
        i = idx[rng.integers(len(idx))]; pt = P[i]                                # ch x bins x frames
        frames = (pt ** 2).sum((0, 1)); on = frames > 0; L = max(1, on.sum())
        e = (pt ** 2).sum(2)                                                      # ch x bins energy
        if cap: e = e * min(1, cap * typical / (e.sum() + 1e-12))                # keep the biggest glass taps from jumping out
        spec = np.sqrt(uniform_filter1d(e, 5, axis=1) / L)                        # smooth spectrum per channel
        prof = frames[on] / frames[on].max(); k = np.argmax(prof)
        tail = prof[k:]; tau = max(.0008, (tail.sum() * 64 / sr) * .9)            # decay from the tap's own energy
        env = np.minimum(1, t / .0002) * np.exp(-np.maximum(t - .0002, 0) / (2 * tau)); env[t > 8 * tau + .004] = 0
        env = np.minimum(1, t / .0002) * np.exp(-np.maximum(t - .0002, 0) / ring); env[t > 8 * ring + .001] = 0
        burst = rng.standard_normal(NF) * env * rng.uniform(*rough); burst[0] += 1          # a single click, with a faint rough edge
        Bf = np.fft.rfft(burst)
        shift = rng.uniform(.94, 1.06); g = rng.uniform(.75, 1.3) / np.sqrt(density)                 # small natural variation
        at = rng.integers(n)
        for c in range(2):
            mag = np.interp(fN / shift, f512, spec[c]) * g
            y = np.fft.irfft(Bf * minphase(mag), NF).astype(np.float32); out[at:at + NF, c] += y
    out[:NF] += out[n:]; out = out[:n]                                            # wrap the end round, so it loops
    print(label, 'taps', count, 'per second', round(count / SEC, 1)); return out
metal = np.where(cent >= 6000)[0]; glass = np.where(cent < 6000)[0]
G = layer(glass, 'glass', density=6, rough=(.3, .8), ring=.0012, cap=2.5); M = layer(metal, 'metal', density=1.0)
w, sr_ = sf.read('wash_gated.wav', dtype='float32'); w = w[:n]
W, *_ = T.synth(w, sr, seed=4, end_spectral=False) if 'end_spectral' in T.synth.__code__.co_varnames else T.synth(w, sr, seed=4)
W = W[:n] if len(W) >= n else np.pad(W, ((0, n - len(W)), (0, 0)))
# levels: outside rain matches the tap-free recording; taps together make up the rest of each band
x, _ = sf.read('storm.wav', dtype='float32'); x = x[int(135 * sr):int(135 * sr) + n]
H, cf = T.filterbank(n, sr, 24)
def bp(y): return np.array([(T.bands(y[:, c], H) ** 2).mean(1) for c in range(2)]).mean(0)
Wp, Gp, Mp, Xp, wp = bp(W), bp(G), bp(M), bp(x), bp(w)
W *= np.sqrt(wp.sum() / Wp.sum())
need = np.clip(Xp - wp, 0, None); have = Gp + Mp
g = np.sqrt(np.median((need / (have + 1e-14))[cf > 2000]))                       # one gain for both tap layers keeps their balance
G *= g; M *= g
for name, y in (('glass', G), ('metal', M), ('outside', W)): sf.write(f'layer_{name}.wav', y, sr, subtype='FLOAT')
mix = W + G + M; sf.write('layers_mix.wav', mix, sr, subtype='FLOAT')
print('band Hz      ', [int(v) for v in cf[::3]])
print('recording dB ', np.round(10 * np.log10(Xp[::3]), 1)); print('new mix dB   ', np.round(10 * np.log10(bp(mix)[::3]), 1))
