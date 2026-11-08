"""Sound texture synthesis, after McDermott & Simoncelli (2011), simplified.
Splits a stereo recording into ERB-spaced bands, takes each band's envelope, and builds new envelopes
that keep (a) each envelope's distribution, (b) its modulation spectrum and (c) every cross-band and
cross-channel relationship, using multivariate IAAFT. New noise carriers supply fresh fine structure.
Everything is circular, so the result loops without a seam."""
import sys, numpy as np, soundfile as sf
from scipy.signal import hilbert, resample

def erb(f): return 21.4 * np.log10(1 + .00437 * f)
def erb_inv(e): return (10 ** (e / 21.4) - 1) / .00437

def filterbank(n, sr, K=32, lo=40, hi=20000):
    f = np.fft.rfftfreq(n, 1 / sr); e = erb(np.clip(f, 1e-9, None)); edges = np.linspace(erb(lo), erb(hi), K + 2)
    H = np.zeros((K, len(f)), np.float32)
    for k in range(K):
        a, c, b = edges[k], edges[k + 1], edges[k + 2]
        m = (e > a) & (e < b); H[k, m] = np.cos((e[m] - c) / (b - a) * np.pi)  # half-overlapping cosines, sum of squares = 1
    return H, erb_inv(edges[1:-1])

def bands(x, H): X = np.fft.rfft(x); return np.fft.irfft(X[None] * H, len(x)).astype(np.float32)

def combine(B, H):
    """Filter each band through its own filter, then add: the matching half of the analysis, so nothing leaks out of band."""
    n = B.shape[1]; acc = np.zeros(n // 2 + 1, np.complex64)
    for k in range(B.shape[0]): acc += np.fft.rfft(B[k]) * H[k]
    return np.fft.irfft(acc, n).astype(np.float32)

def unit(car):
    """Fine structure with a flat envelope. A floor stops near-silent moments turning into spikes."""
    e = np.abs(hilbert(car, axis=1)); return car / (e + .1 * np.sqrt(np.mean(e ** 2, axis=1, keepdims=True)))

def iaaft(E, iters, rng, end_spectral=True):
    """E: channels x time envelopes. Keeps amplitude spectra, cross-spectra (via shared phase rotation) and distributions."""
    F0 = np.fft.rfft(E, axis=1); A = np.abs(F0); sorted_ = np.sort(E, axis=1)
    phi = rng.uniform(0, 2 * np.pi, F0.shape[1]); phi[0] = 0
    Y = np.fft.irfft(F0 * np.exp(1j * phi)[None], E.shape[1], axis=1)
    for it in range(iters):
        rank = np.argsort(np.argsort(Y, axis=1), axis=1); Y = np.take_along_axis(sorted_, rank, axis=1)  # match distributions
        F = np.fft.rfft(Y, axis=1); phi = np.angle(np.sum(F * np.conj(F0), axis=0))  # best common rotation
        Y = np.fft.irfft(F0 * np.exp(1j * phi)[None], E.shape[1], axis=1)              # restore spectra and cross-spectra
    if not end_spectral:
        rank = np.argsort(np.argsort(Y, axis=1), axis=1); Y = np.take_along_axis(sorted_, rank, axis=1)
    return np.clip(Y, 0, None)

def synth(x, sr, seed=1, K=32, dec=8, iters=30, rounds=3, end_spectral=True):
    rng = np.random.default_rng(seed); n = len(x) - len(x) % (2 * dec); x = x[:n]
    H, cf = filterbank(n, sr, K); C = x.shape[1]
    sub = np.concatenate([bands(x[:, c], H) for c in range(C)])               # (C*K, n)
    env = np.abs(hilbert(sub, axis=1)).astype(np.float32)
    small = resample(env, n // dec, axis=1)                                     # circular decimation
    target = iaaft(small, iters, rng, end_spectral)
    newenv = np.clip(resample(target, n, axis=1), 0, None).astype(np.float32)
    carrier = unit(np.concatenate([bands(rng.standard_normal(n), H) for c in range(C)]))
    out = newenv * carrier
    for r in range(rounds):  # refiltering softens envelopes, so re-impose them a few times
        y = np.stack([combine(out[c * K:(c + 1) * K], H) for c in range(C)], 1)
        if r == rounds - 1: break
        out = np.concatenate([bands(y[:, c], H) for c in range(C)]); out = (newenv * unit(out)).astype(np.float32)
    y *= np.sqrt(np.mean(x ** 2) / np.mean(y ** 2))
    return y, sub, env, cf

def stats(sub, K):
    env = np.abs(hilbert(sub, axis=1)); m = env.mean(1); v = env.var(1)
    kurt = ((env - m[:, None]) ** 4).mean(1) / v ** 2
    corr = np.corrcoef(env[:K][::4])
    return m / m.sum(), kurt, corr

if __name__ == '__main__':
    src, start, dur, out = sys.argv[1], float(sys.argv[2]), float(sys.argv[3]), sys.argv[4]
    x, sr = sf.read(src, dtype='float32'); x = x[int(start * sr):int((start + dur) * sr)]
    y, sub, env, cf = synth(x, sr, seed=int(sys.argv[5]) if len(sys.argv) > 5 else 1)
    sf.write(out, y.astype(np.float32), sr, subtype='FLOAT')
    H, _ = filterbank(len(y), sr); K = 32
    sb = bands(y[:, 0], H); a = stats(sub[:K], K); b = stats(sb, K)
    pick = [2, 8, 14, 20, 26, 30]
    print('band Hz     ', [int(cf[i]) for i in pick])
    print('kurt orig   ', np.round(a[1][pick], 1)); print('kurt synth  ', np.round(b[1][pick], 1))
    print('power orig  ', np.round(10 * np.log10(a[0][pick]), 1)); print('power synth ', np.round(10 * np.log10(b[0][pick]), 1))
    print('mean |corr diff|', round(float(np.abs(a[2] - b[2]).mean()), 3), ' mean orig corr', round(float(a[2].mean()), 3))
