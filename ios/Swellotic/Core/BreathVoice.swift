import Foundation

/// A struck sound: its note, how fast it is struck, how loud it is and its partials.
struct StruckRecipe {
    struct Partial { let ratio: Double; let amp: Double; let fade: Double }

    let noteOffset: Double
    let attack: Double
    let level: Double
    let partials: [Partial]

    // These match app.js. Struck sounds use A on the in-breath and D on the out-breath, which sit with the generated music.
    static let chime = StruckRecipe(noteOffset: 12, attack: 0.02, level: 0.3, partials: [.init(ratio: 1, amp: 1, fade: 1)])
    static let piano = StruckRecipe(noteOffset: 0, attack: 0.015, level: 0.3, partials: [
        .init(ratio: 1, amp: 1, fade: 1), .init(ratio: 2, amp: 0.16, fade: 0.7), .init(ratio: 3, amp: 0.05, fade: 0.5)])
    static let wood = StruckRecipe(noteOffset: 12, attack: 0.006, level: 0.34, partials: [
        .init(ratio: 1, amp: 1, fade: 1), .init(ratio: 3.9, amp: 0.12, fade: 0.3)])
    static let bowl = StruckRecipe(noteOffset: 0, attack: 0.35, level: 0.2, partials: [
        .init(ratio: 1, amp: 0.7, fade: 1), .init(ratio: 1.004, amp: 0.7, fade: 1), .init(ratio: 2.71, amp: 0.16, fade: 0.6)])
    static let gong = StruckRecipe(noteOffset: -24, attack: 0.05, level: 0.3, partials: [
        .init(ratio: 1, amp: 1, fade: 1), .init(ratio: 1.48, amp: 0.5, fade: 0.8), .init(ratio: 2.02, amp: 0.34, fade: 0.65),
        .init(ratio: 2.76, amp: 0.16, fade: 0.5), .init(ratio: 3.41, amp: 0.08, fade: 0.35)])

    static func recipe(for sound: BreathSound) -> StruckRecipe? {
        switch sound {
        case .chime: return chime
        case .piano: return piano
        case .wood: return wood
        case .bowl: return bowl
        case .gong: return gong
        case .tone, .ocean, .silent: return nil
        }
    }
}

/// One breath sound. Each lasts the whole in-breath or out-breath and falls silent as the next one begins.
/// Plain value storage only, so voices can be reused on the audio thread without allocating.
struct CueVoice {
    var active = false
    private(set) var sound: BreathSound = .bowl
    private var isIn = true
    private var start: Int64 = 0
    private var length = 0.0

    // Struck sounds
    private var attack = 0.0
    private var body = 0.0
    private var partialCount = 0
    private var increments = SIMD8<Double>()
    private var peaks = SIMD8<Double>()
    private var exponents = SIMD8<Double>(repeating: 1)
    private var phases = SIMD8<Double>()

    // Gliding sounds: Soft hum and Ocean
    private var glideFrom = 0.0
    private var glideTo = 0.0
    private var phase = 0.0
    private var filter = Biquad(.bandpass, frequency: 400, q: 0.7, sampleRate: 48_000)
    private var noise = Noise(seed: 0x5EED_1234)
    private var counter = 0

    // Fading out early, when the breath sound is changed mid-breath
    private var releasing = false
    private var release = 1.0
    private var releaseCoeff = 1.0
    private var releaseEnd: Int64 = 0

    var isReleasing: Bool { releasing }

    /// Starts a sound at frame `start` whose shape lasts `length` seconds.
    mutating func trigger(_ sound: BreathSound, isIn: Bool, start: Int64, length: Double, sampleRate: Double) {
        guard sound != .silent, length > 0.01 else { active = false; return }
        self.sound = sound
        self.isIn = isIn
        self.start = start
        self.length = length
        active = true
        releasing = false
        release = 1
        phase = 0
        phases = SIMD8<Double>()
        counter = 0
        switch sound {
        case .tone:
            glideFrom = midiToHz(isIn ? 50 : 55)
            glideTo = midiToHz(isIn ? 55 : 50)
        case .ocean:
            glideFrom = isIn ? 220 : 520
            glideTo = isIn ? 620 : 180
            filter = Biquad(.bandpass, frequency: glideFrom, q: 0.7, sampleRate: sampleRate)
        default:
            guard let recipe = StruckRecipe.recipe(for: sound) else { active = false; return }
            let base = midiToHz((isIn ? 69 : 62) + recipe.noteOffset)
            attack = recipe.attack
            body = max(0.05, length - recipe.attack - 0.002)
            partialCount = min(8, recipe.partials.count)
            for k in 0..<partialCount {
                let p = recipe.partials[k]
                increments[k] = base * p.ratio / sampleRate
                peaks[k] = recipe.level * p.amp * 0.75
                exponents[k] = 1 / p.fade
            }
        }
    }

    /// Fades the sound out quickly, for when the breath sound changes mid-breath.
    mutating func beginRelease(at frame: Int64, sampleRate: Double) {
        guard active, !releasing else { return }
        releasing = true
        releaseCoeff = exp(-1 / (0.04 * sampleRate))
        releaseEnd = frame + Int64(0.3 * sampleRate)
    }

    // In-breaths swell and out-breaths settle, matching app.js.
    @inline(__always) static func envIn(_ x: Double) -> Double { sin(Double.pi * pow(x, 1.4)) }
    @inline(__always) static func envOut(_ x: Double) -> Double { sin(Double.pi * pow(x, 0.7)) }
    @inline(__always) static func swell(_ x: Double) -> Double {
        let s = sin(Double.pi / 2 * x)
        return (0.35 + 0.65 * s * s) * min(1, (1 - x) / 0.12)
    }
    @inline(__always) static func settle(_ x: Double) -> Double { pow(max(0, 1 - x), 1.6) }

    mutating func next(frame: Int64, sampleRate: Double) -> Double {
        let t = Double(frame - start) / sampleRate
        if t < 0 { return 0 }
        var s = 0.0
        switch sound {
        case .tone, .ocean:
            if t >= length {
                if t >= length + 0.02 { active = false }
                return 0
            }
            let x = t / length
            let shape = isIn ? Self.envIn(x) : Self.envOut(x)
            let f = glideFrom + (glideTo - glideFrom) * x
            if sound == .tone {
                s = sine(phase) * shape * 0.3
                phase = wrap(phase + f / sampleRate)
            } else {
                if counter == 0 { filter.set(frequency: f, q: 0.7, sampleRate: sampleRate) }
                counter = (counter + 1) & 31
                s = filter.process(noise.white()) * shape * 0.4
            }
        case .silent:
            active = false
            return 0
        default:
            let end = attack + 0.001 + body
            if t >= end {
                if t >= end + 0.02 { active = false }
                return 0
            }
            let ramp = t < attack ? t / attack : 1
            let x = t < attack + 0.001 ? 0 : (t - attack - 0.001) / body
            let shape = isIn ? Self.swell(x) : Self.settle(x)
            for k in 0..<partialCount {
                // Higher partials fade sooner, like a real struck note.
                let env = peaks[k] * pow(shape, exponents[k]) * ramp
                s += sine(phases[k]) * env
                phases[k] = wrap(phases[k] + increments[k])
            }
        }
        if releasing {
            release *= releaseCoeff
            if frame >= releaseEnd { active = false; return 0 }
            s *= release
        }
        return s
    }
}
