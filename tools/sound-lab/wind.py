"""A seamless wind loop: noise whose level and colour follow slow, irregular gusts, with a faint whistle at the peaks."""
import numpy as np, soundfile as sf
sr = 44100; SEC = 60; N = 2048; HOP = 512; F = SEC * sr // HOP; rng = np.random.default_rng(21)
def slow(cut_hz, seed):  # smooth random curve that loops
    r = np.random.default_rng(seed); X = np.fft.rfft(r.standard_normal(F)); fr = np.fft.rfftfreq(F, HOP / sr)
    X *= np.exp(-(fr / cut_hz) ** 2); y = np.fft.irfft(X, F); return (y - y.mean()) / y.std()
f = np.fft.rfftfreq(N, 1 / sr); w = np.hanning(N); out = np.zeros((SEC * sr, 2))
for c in range(2):
    gust = np.exp(.55 * slow(.06, 1 + c * 0) + .35 * slow(.02, 2) + .15 * slow(.25, 3 + c))   # same big gusts both sides, small differences
    gust = np.roll(gust, c * 6)                                                                    # one side a touch later, for width
    lvl = (gust / gust.max()) ** 1.3
    centre = 180 + 520 * lvl                                                                       # stronger gusts sound higher
    whistle = 700 + 250 * slow(.03, 7)
    for i in range(F):
        shape = 1 / np.sqrt(1 + (f / 60) ** 2) * (1 + 2.5 * np.exp(-np.log2(np.maximum(f, 1) / centre[i]) ** 2 / .5)) / (1 + (f / 3000) ** 2)
        shape += .25 * lvl[i] ** 3 * np.exp(-((f - whistle[i]) / 18) ** 2)                         # faint whistle only near the peaks
        mag = shape * (.15 + lvl[i]); ph = rng.uniform(0, 2 * np.pi, len(f))
        seg = np.fft.irfft(mag * np.exp(1j * ph), N) * w; idx = (i * HOP + np.arange(N)) % (SEC * sr); out[idx, c] += seg
out /= np.abs(out).max() / .89; sf.write('wind.wav', out.astype(np.float32), 22050 if False else sr, subtype='PCM_16')
print('wind loop', SEC, 's, gust range dB', round(20 * np.log10(lvl.max() / lvl.min()), 1))
