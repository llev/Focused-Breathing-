import Foundation

/// One in-breath or out-breath, in seconds on the audio clock.
struct BreathPhase: Equatable, Sendable {
    var isIn: Bool
    var start: Double
    var end: Double
    var bpm: Double

    var duration: Double { end - start }

    func progress(at t: Double) -> Double {
        guard end > start else { return 0 }
        return min(1, max(0, (t - start) / (end - start)))
    }

    /// How full the breath is, from 0 (empty) to 1 (full), eased so the visuals turn gently.
    func level(at t: Double) -> Double {
        let eased = 0.5 - 0.5 * cos(Double.pi * progress(at: t))
        return isIn ? eased : 1 - eased
    }
}

/// What the visuals need for one frame.
struct BreathFrame: Equatable, Sendable {
    var phase: BreathPhase
    var time: Double
    var level: Double
}

/// The settings that decide how long each breath lasts.
struct Pacing: Equatable, Sendable {
    var bpm: Double = 6
    var inhaleShare: Double = 0.5
    var ease = false
    /// "Slow down gradually" only applies during a session, measured from its start.
    var sessionStart: Double?

    func pace(at t: Double) -> Double {
        guard ease, let start = sessionStart, bpm < 10 else { return bpm }
        return 10 + (bpm - 10) * min(1, max(0, (t - start) / 180))
    }
}

/// The one timeline of breathing phases. Sound and visuals both read from it, so they stay in step.
/// Changes to the pace apply from the next breath.
struct BreathTimeline: Sendable {
    private(set) var current: BreathPhase
    private var plannedOut: BreathPhase?

    init(startingAt start: Double, pacing: Pacing) {
        let cycle = Self.cycle(at: start, pacing: pacing)
        current = cycle.in
        plannedOut = cycle.out
    }

    static func cycle(at start: Double, pacing: Pacing) -> (in: BreathPhase, out: BreathPhase) {
        let bpm = min(30, max(0.5, pacing.pace(at: start)))
        let length = 60 / bpm
        let inhale = length * pacing.inhaleShare
        return (BreathPhase(isIn: true, start: start, end: start + inhale, bpm: bpm),
                BreathPhase(isIn: false, start: start + inhale, end: start + length, bpm: bpm))
    }

    /// Moves on to the phase that contains `t`. Returns true if the phase changed.
    @discardableResult
    mutating func advance(to t: Double, pacing: Pacing) -> Bool {
        guard t >= current.end else { return false }
        // After a long gap, such as a preview left in the background, start afresh instead of replaying every breath.
        if t - current.end > 120 {
            self = BreathTimeline(startingAt: t, pacing: pacing)
            return true
        }
        while t >= current.end {
            if let out = plannedOut {
                current = out
                plannedOut = nil
            } else {
                let cycle = Self.cycle(at: current.end, pacing: pacing)
                current = cycle.in
                plannedOut = cycle.out
            }
        }
        return true
    }
}
