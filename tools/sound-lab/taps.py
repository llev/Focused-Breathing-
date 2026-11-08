"""Find the taps in a stretch of rain, keep each tap's time-frequency shape, and split the taps into groups."""
import sys, numpy as np, soundfile as sf
from scipy.ndimage import maximum_filter1d, uniform_filter1d
N, HOP = 512, 64
def stft(x):
    w = np.hanning(N).astype(np.float32); F = (len(x) - N) // HOP + 1
    idx = np.arange(N)[None] + HOP * np.arange(F)[:, None]; return np.fft.rfft(x[idx] * w, axis=1).T.astype(np.complex64)  # bins x frames
def background(P, block=172):  # 40th percentile of power in ~0.25 s blocks, smoothed over ~1.5 s
    B = P.shape[1] // block; q = np.percentile(P[:, :B * block].reshape(P.shape[0], B, block), 40, axis=2)
    q = uniform_filter1d(q, 6, axis=1, mode='nearest'); t = (np.arange(P.shape[1]) / block).clip(0, B - 1)
    return np.stack([np.interp(t, np.arange(B), row) for row in q]).astype(np.float32)
if __name__ == '__main__':
    x, sr = sf.read(sys.argv[1], dtype='float32'); a, b = float(sys.argv[2]), float(sys.argv[3]); x = x[int(a * sr):int(b * sr)]
    S = [stft(x[:, c]) for c in range(2)]; P = [np.abs(s) ** 2 for s in S]; Bg = [background(p) for p in P]
    f = np.fft.rfftfreq(N, 1 / sr); hi = f > 1500
    E = [np.clip(p - 2 * bg, 0, None) for p, bg in zip(P, Bg)]
    det = (E[0][hi] + E[1][hi]).sum(0) / ((Bg[0][hi] + Bg[1][hi]).sum(0) + 1e-12)
    peaks = np.where((det > 1.0) & (det == maximum_filter1d(det, 5)))[0]; peaks = peaks[(peaks > 2) & (peaks < det.size - 30)]
    clean = [np.where(p > 4 * bg, e, 0) for p, bg, e in zip(P, Bg, E)]        # only what clearly stands out
    high = (clean[0][hi] + clean[1][hi]).sum(0); patches = []
    for k, t in enumerate(peaks):
        nxt = peaks[k + 1] if k + 1 < len(peaks) else t + 28; end = min(t + 28, nxt - 1)
        top = high[t - 1:t + 2].max(); j = t + 1
        while j < end and high[j] > .12 * top: j += 1                         # stop where the tap fades or the next begins
        pt = np.stack([np.sqrt(c[:, t - 2:t + 28]) for c in clean]); pt[:, :, j - t + 2:] = 0; patches.append(pt)
    patches = np.stack(patches).astype(np.float16)                              # events x ch x bins x 30 frames
    patches[:, :, f < 1000, :] = 0                                           # the low range belongs to the outside-rain layer
    en = patches.astype(np.float32) ** 2; spec = en.sum((1, 3)); cent = (spec * f).sum(1) / (spec.sum(1) + 1e-12)
    prof = en.sum((1, 2)); dur = (prof > prof.max(1, keepdims=True) * .1).sum(1) * HOP / sr * 1000
    print('taps', len(peaks), 'per second', round(len(peaks) / (b - a), 1))
    for lo, hi_ in ((0, 2500), (2500, 4000), (4000, 6000), (6000, 8000), (8000, 11000), (11000, 15000), (15000, 22050)):
        m = (cent >= lo) & (cent < hi_); print(f'  centre {lo}-{hi_} Hz: {m.sum():5d} taps, median length {np.median(dur[m]) if m.any() else 0:.1f} ms, median level {10*np.log10(np.median(en[m].sum((1,2,3)))+1e-12) if m.any() else 0:.1f} dB')
    np.savez_compressed(sys.argv[4], patches=patches, cent=cent, dur=dur, t=peaks, sr=sr, rate=len(peaks) / (b - a))
    # wash: the same stretch with the taps pulled down to the background
    for c in range(2):
        g = np.minimum(1, np.sqrt(2 * Bg[c] / (P[c] + 1e-12))); S[c] = S[c] * g
    w = np.hanning(N).astype(np.float32); F = S[0].shape[1]; L = (F - 1) * HOP + N; out = np.zeros((L, 2), np.float32); norm = np.zeros(L, np.float32)
    for c in range(2):
        fr = np.fft.irfft(S[c].T, N, axis=1) * w
        for i in range(F): out[i * HOP:i * HOP + N, c] += fr[i]
    for i in range(F): norm[i * HOP:i * HOP + N] += w ** 2
    out /= np.maximum(norm, 1e-3)[:, None]; sf.write(sys.argv[5], out, sr, subtype='FLOAT')
    print('wash level', round(10 * np.log10(np.mean(out ** 2)), 1), 'dB, recording', round(10 * np.log10(np.mean(x ** 2)), 1), 'dB')
