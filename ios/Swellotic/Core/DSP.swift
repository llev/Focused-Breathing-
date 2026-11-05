import Foundation

// Small building blocks for generating sound. Everything here is a plain value type with no heap storage,
// so it is safe to use on the audio thread.

/// A fast random number source (xorshift).
struct Noise {
    private var state: UInt64

    init(seed: UInt64) { state = seed == 0 ? 0x9E37_79B9_7F4A_7C15 : seed }

    /// 0 up to but not including 1.
    @inline(__always) mutating func uniform() -> Double {
        state ^= state << 13
        state ^= state >> 7
        state ^= state << 17
        return Double(state >> 11) * (1.0 / 9_007_199_254_740_992.0)
    }

    /// -1 to 1.
    @inline(__always) mutating func white() -> Double { uniform() * 2 - 1 }
}

/// Turns white noise into pink noise, using the same filter as the web app.
struct PinkFilter {
    private var b0 = 0.0, b1 = 0.0, b2 = 0.0

    @inline(__always) mutating func process(_ w: Double) -> Double {
        b0 = 0.99765 * b0 + w * 0.099046
        b1 = 0.963 * b1 + w * 0.2965164
        b2 = 0.57 * b2 + w * 1.0526913
        return (b0 + b1 + b2 + w * 0.1848) * 0.11
    }
}

/// Turns white noise into brown noise, using the same filter as the web app.
struct BrownFilter {
    private var last = 0.0

    @inline(__always) mutating func process(_ w: Double) -> Double {
        last = (last + 0.02 * w) / 1.02
        return last * 3.5
    }
}

/// A standard two-pole filter (RBJ cookbook), matching Web Audio's lowpass, highpass and bandpass.
struct Biquad {
    enum Kind { case lowpass, highpass, bandpass }

    let kind: Kind
    private var b0 = 1.0, b1 = 0.0, b2 = 0.0, a1 = 0.0, a2 = 0.0
    private var z1 = 0.0, z2 = 0.0

    init(_ kind: Kind, frequency: Double, q: Double = 0.7071, sampleRate: Double) {
        self.kind = kind
        set(frequency: frequency, q: q, sampleRate: sampleRate)
    }

    mutating func set(frequency: Double, q: Double = 0.7071, sampleRate: Double) {
        let f = min(max(frequency, 10), sampleRate * 0.45)
        let w = 2 * Double.pi * f / sampleRate
        let cw = cos(w)
        let alpha = sin(w) / (2 * max(q, 0.01))
        let a0 = 1 + alpha
        switch kind {
        case .lowpass:
            b0 = (1 - cw) / 2; b1 = 1 - cw; b2 = (1 - cw) / 2
        case .highpass:
            b0 = (1 + cw) / 2; b1 = -(1 + cw); b2 = (1 + cw) / 2
        case .bandpass:
            b0 = alpha; b1 = 0; b2 = -alpha
        }
        b0 /= a0; b1 /= a0; b2 /= a0
        a1 = -2 * cw / a0
        a2 = (1 - alpha) / a0
    }

    @inline(__always) mutating func process(_ x: Double) -> Double {
        let y = b0 * x + z1
        z1 = b1 * x - a1 * y + z2
        z2 = b2 * x - a2 * y
        return y
    }
}

/// Eases a level towards a target, like Web Audio's setTargetAtTime.
struct Smoother {
    var value: Double
    private(set) var coeff: Double

    init(value: Double, timeConstant: Double, sampleRate: Double) {
        self.value = value
        coeff = 1 - exp(-1 / (timeConstant * sampleRate))
    }

    @inline(__always) mutating func next(toward target: Double) -> Double {
        value += (target - value) * coeff
        return value
    }
}

/// A fade that moves in a straight line or eases towards its target.
struct Fade {
    private(set) var value = 0.0
    private var target = 0.0
    private var step = 0.0
    private var coeff = 0.0
    private var linear = true

    mutating func jump(to v: Double) {
        value = v; target = v; step = 0; linear = true
    }

    mutating func ramp(to t: Double, seconds: Double, sampleRate: Double) {
        target = t
        linear = true
        step = (t - value) / max(1, seconds * sampleRate)
    }

    mutating func glide(to t: Double, timeConstant: Double, sampleRate: Double) {
        target = t
        linear = false
        coeff = 1 - exp(-1 / (timeConstant * sampleRate))
    }

    @inline(__always) mutating func next() -> Double {
        if linear {
            if value != target {
                value += step
                if step == 0 || (step > 0 && value >= target) || (step < 0 && value <= target) { value = target }
            }
        } else {
            value += (target - value) * coeff
            if target == 0 && value < 1e-7 { jump(to: 0) }
        }
        return value
    }

    /// True once the fade has settled at silence.
    var isSilent: Bool { target == 0 && value < 1e-6 }
}

@inline(__always) func sine(_ phase: Double) -> Double { sin(2 * Double.pi * phase) }

/// A triangle wave from -1 to 1 for a phase of 0 to 1.
@inline(__always) func triangle(_ phase: Double) -> Double { 4 * abs(phase - 0.5) - 1 }

@inline(__always) func wrap(_ phase: Double) -> Double { phase >= 1 ? phase - 1 : phase }
