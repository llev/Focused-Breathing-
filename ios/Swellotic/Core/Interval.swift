import Foundation

/// Interval sessions: a swell for focus and a rest for a quiet break take turns on the session clock, as in app.js.
struct IntervalPlan: Equatable, Sendable {
    var swell: Double
    var rest: Double

    /// Whether `elapsed` seconds into a session falls in a rest, and how long is left of the current swell or rest.
    func segment(at elapsed: Double) -> (resting: Bool, left: Double) {
        guard swell > 0 else { return (false, 0) }
        let cycle = swell + max(0, rest)
        let pos = max(0, elapsed).truncatingRemainder(dividingBy: cycle)
        return pos < swell ? (false, swell - pos) : (true, cycle - pos)
    }

    /// How long a session of `rounds` swells lasts, ending after the last swell. 0 means until stopped.
    func length(rounds: Int) -> Double {
        rounds > 0 ? Double(rounds) * swell + Double(rounds - 1) * rest : 0
    }
}

/// A soft two-note chime that marks each change between swell and rest. It plays on its own path,
/// so it's heard even while a rest has faded everything else.
struct Chime {
    private var start: Int64 = -1
    private var phases = SIMD4<Double>()
    private var steps = SIMD4<Double>()
    private var env = SIMD2<Double>()
    private var peaks = SIMD2<Double>()
    private var decay = 1.0

    /// Lower for a rest, higher for a swell, matching the web app's notes.
    mutating func ring(note: Double, at frame: Int64, level: Double, sampleRate: Double) {
        start = frame
        let a = midiToHz(note), b = midiToHz(note + 7)
        steps = SIMD4(a / sampleRate, a * 2.76 / sampleRate, b / sampleRate, b * 2.76 / sampleRate)
        phases = SIMD4<Double>()
        peaks = SIMD2(level, level * 0.8)
        env = SIMD2<Double>()
        decay = pow(0.0003 / max(level, 0.001), 1 / (3.48 * sampleRate))
    }

    @inline(__always) mutating func next(frame: Int64, sampleRate: Double) -> Double {
        guard start >= 0 else { return 0 }
        let t = Double(frame - start) / sampleRate
        if t > 3.95 { start = -1; return 0 }
        var s = 0.0
        // The second note follows 0.35 seconds after the first.
        for n in 0..<2 {
            let local = t - (n == 0 ? 0 : 0.35)
            if local < 0 { continue }
            if local < 0.02 {
                env[n] = peaks[n] * local / 0.02
            } else if local < 3.5 {
                env[n] *= decay
            } else {
                env[n] = 0
            }
            s += (sine(phases[n * 2]) + 0.12 * sine(phases[n * 2 + 1])) * env[n]
            phases[n * 2] = wrap(phases[n * 2] + steps[n * 2])
            phases[n * 2 + 1] = wrap(phases[n * 2 + 1] + steps[n * 2 + 1])
        }
        return s
    }
}

/// Fades sound out for a rest, shortly after the chime starts, and back in for the next swell.
struct RestFader {
    private(set) var value = 1.0
    private var target = 1.0
    private var pendingTarget = 1.0
    private var pendingFrom: Int64 = 0
    private var coeff = 0.0

    mutating func reset() {
        value = 1; target = 1; pendingTarget = 1; pendingFrom = 0
    }

    mutating func set(resting: Bool, at frame: Int64, sampleRate: Double) {
        pendingTarget = resting ? 0 : 1
        pendingFrom = frame + Int64((resting ? 0.6 : 0.2) * sampleRate)
        coeff = 1 - exp(-1 / ((resting ? 0.7 : 0.5) * sampleRate))
    }

    @inline(__always) mutating func next(frame: Int64) -> Double {
        if frame >= pendingFrom { target = pendingTarget }
        if value != target {
            value += (target - value) * coeff
            if abs(target - value) < 1e-6 { value = target }
        }
        return value
    }
}
