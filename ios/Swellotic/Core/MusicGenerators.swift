import Foundation

// Generated background sounds, ported from startVoice() in app.js. Each makes stereo samples one at a time,
// allocates nothing after it's created, and keeps its own clock so it can be restarted with reset().
// No rhythmic amplitude modulation: the slow drifts here are far below anything rhythmic (see CLAUDE.md).

protocol MusicGenerator: AnyObject {
    func reset()
    func next() -> (Double, Double)
}

func makeGenerator(_ track: MusicTrack, sampleRate: Double, controls: SynthControls) -> MusicGenerator? {
    switch track {
    case .brown: return BrownNoiseSound(sampleRate: sampleRate)
    case .pink: return PinkNoiseSound(sampleRate: sampleRate)
    case .rain: return RainSound(sampleRate: sampleRate)
    case .beach: return BeachSound(sampleRate: sampleRate)
    case .stream: return StreamSound(sampleRate: sampleRate)
    case .wind: return WindSound(sampleRate: sampleRate)
    case .fire: return FireSound(sampleRate: sampleRate, controls: controls)
    case .ambient: return AmbientSound(sampleRate: sampleRate)
    case .keys: return SoftKeysSound(sampleRate: sampleRate)
    case .green: return GreenNoiseSound(sampleRate: sampleRate)
    case .window: return RainMoodSound(sampleRate: sampleRate, controls: controls, storm: false)
    case .storm: return RainMoodSound(sampleRate: sampleRate, controls: controls, storm: true)
    case .park: return ParkSound(sampleRate: sampleRate, controls: controls)
    case .hill: return WindHillSound(sampleRate: sampleRate, controls: controls)
    case .classical, .musicApp, .breathOnly: return nil
    }
}

final class BrownNoiseSound: MusicGenerator {
    private var noise = Noise(seed: 0xB0)
    private var left = BrownFilter(), right = BrownFilter()
    init(sampleRate: Double) {}
    func reset() {}
    func next() -> (Double, Double) {
        (left.process(noise.white()) * 0.9, right.process(noise.white()) * 0.9)
    }
}

final class PinkNoiseSound: MusicGenerator {
    private var noise = Noise(seed: 0x91)
    private var left = PinkFilter(), right = PinkFilter()
    init(sampleRate: Double) {}
    func reset() {}
    func next() -> (Double, Double) {
        (left.process(noise.white()) * 0.75, right.process(noise.white()) * 0.75)
    }
}

final class RainSound: MusicGenerator {
    private var noise = Noise(seed: 0x4A1)
    private var brownL = BrownFilter(), brownR = BrownFilter()
    private var hpL, hpR, lpL, lpR: Biquad

    init(sampleRate sr: Double) {
        let hpLFilter = Biquad(.highpass, frequency: 1100, sampleRate: sr)
        hpL = hpLFilter; hpR = hpLFilter
        let lpLFilter = Biquad(.lowpass, frequency: 6500, sampleRate: sr)
        lpL = lpLFilter; lpR = lpLFilter
    }
    func reset() {}
    func next() -> (Double, Double) {
        let l = lpL.process(hpL.process(noise.white())) * 0.16 + brownL.process(noise.white()) * 0.3
        let r = lpR.process(hpR.process(noise.white())) * 0.16 + brownR.process(noise.white()) * 0.3
        return (l, r)
    }
}

/// Slow, soft waves: a low rumble with filtered noise that swells every 8 to 13 seconds.
final class BeachSound: MusicGenerator {
    private let sr: Double
    private var noise = Noise(seed: 0xBEAC)
    private var brownL = BrownFilter(), brownR = BrownFilter()
    private var lpL, lpR: Biquad
    private var t = 0.0
    private var waveStart = 0.1, waveLength = 10.0, peak = 0.26, peakFreq = 880.0
    private var swell = 0.04, freq = 320.0
    private var counter = 0

    init(sampleRate: Double) {
        sr = sampleRate
        let lpLFilter = Biquad(.lowpass, frequency: 320, sampleRate: sampleRate)
        lpL = lpLFilter; lpR = lpLFilter
        newWave()
    }

    func reset() {
        t = 0; waveStart = 0.1; counter = 0
        newWave()
    }

    private func newWave() {
        waveLength = 8 + noise.uniform() * 5
        peak = 0.2 + noise.uniform() * 0.12
        peakFreq = 760 + noise.uniform() * 260
    }

    private func updateWave() {
        guard t >= waveStart else { swell = 0.04; freq = 320; return }
        var x = (t - waveStart) / waveLength
        while x >= 1 {
            waveStart += waveLength
            newWave()
            x = (t - waveStart) / waveLength
        }
        if x < 0.42 {
            let k = x / 0.42
            swell = 0.04 + (peak - 0.04) * k
            freq = 320 + (peakFreq - 320) * k
        } else {
            let k = (x - 0.42) / 0.58
            swell = peak + (0.04 - peak) * k
            freq = peakFreq + (320 - peakFreq) * k
        }
    }

    func next() -> (Double, Double) {
        if counter == 0 {
            updateWave()
            lpL.set(frequency: freq, sampleRate: sr)
            lpR.set(frequency: freq, sampleRate: sr)
        }
        counter = (counter + 1) & 31
        t += 1 / sr
        let l = brownL.process(noise.white()) * 0.3 + lpL.process(noise.white()) * swell
        let r = brownR.process(noise.white()) * 0.3 + lpR.process(noise.white()) * swell
        return (l, r)
    }
}

final class StreamSound: MusicGenerator {
    private let sr: Double
    private var noise = Noise(seed: 0x57E)
    private var pinkL = PinkFilter(), pinkR = PinkFilter()
    private var lowL, lowR, highL, highR: Biquad
    private var t = 0.0
    private var counter = 0

    init(sampleRate: Double) {
        sr = sampleRate
        let lowLFilter = Biquad(.bandpass, frequency: 800, q: 0.5, sampleRate: sampleRate)
        lowL = lowLFilter; lowR = lowLFilter
        let highLFilter = Biquad(.bandpass, frequency: 1900, q: 1, sampleRate: sampleRate)
        highL = highLFilter; highR = highLFilter
    }
    func reset() { t = 0; counter = 0 }
    func next() -> (Double, Double) {
        if counter == 0 {
            let f = 1900 + 320 * sine(0.13 * t)
            highL.set(frequency: f, q: 1, sampleRate: sr)
            highR.set(frequency: f, q: 1, sampleRate: sr)
        }
        counter = (counter + 1) & 31
        t += 1 / sr
        let pl = pinkL.process(noise.white()), pr = pinkR.process(noise.white())
        return (lowL.process(pl) * 1.1 + highL.process(pl) * 0.6,
                lowR.process(pr) * 1.1 + highR.process(pr) * 0.6)
    }
}

final class WindSound: MusicGenerator {
    private let sr: Double
    private var noise = Noise(seed: 0x3D)
    private var pinkL = PinkFilter(), pinkR = PinkFilter()
    private var bandL, bandR: Biquad
    private var t = 0.0
    private var counter = 0
    private var gain = 0.9

    init(sampleRate: Double) {
        sr = sampleRate
        let bandLFilter = Biquad(.bandpass, frequency: 380, q: 0.8, sampleRate: sampleRate)
        bandL = bandLFilter; bandR = bandLFilter
    }
    func reset() { t = 0; counter = 0 }
    func next() -> (Double, Double) {
        if counter == 0 {
            let f = 380 + 170 * sine(0.07 * t)
            bandL.set(frequency: f, q: 0.8, sampleRate: sr)
            bandR.set(frequency: f, q: 0.8, sampleRate: sr)
            gain = 0.9 + 0.3 * sine(0.05 * t)
        }
        counter = (counter + 1) & 31
        t += 1 / sr
        return (bandL.process(pinkL.process(noise.white())) * gain,
                bandR.process(pinkR.process(noise.white())) * gain)
    }
}

/// A low rumble with random crackles, about three a second. Its Mix sliders are Fire and Crackles.
final class FireSound: MusicGenerator {
    private struct Crackle { var gain = 0.0; var decay = 1.0; var remaining = 0 }

    private let sr: Double
    private var noise = Noise(seed: 0xF1)
    private var brownL = BrownFilter(), brownR = BrownFilter()
    private var lowL, lowR, hpL, hpR: Biquad
    private var crackles = [Crackle](repeating: Crackle(), count: 6)
    private var t = 0.0
    private var nextCrackle = 0.2
    private let controls: SynthControls
    private var gains: LayerGains
    private var counter = 0

    init(sampleRate: Double, controls: SynthControls) {
        sr = sampleRate
        self.controls = controls
        var g = LayerGains(sampleRate: sampleRate)
        g.read(controls); g.snap()
        gains = g
        let lowLFilter = Biquad(.lowpass, frequency: 480, sampleRate: sampleRate)
        lowL = lowLFilter; lowR = lowLFilter
        let hpLFilter = Biquad(.highpass, frequency: 1500, sampleRate: sampleRate)
        hpL = hpLFilter; hpR = hpLFilter
    }

    func reset() {
        t = 0; nextCrackle = 0.2
        for i in crackles.indices { crackles[i].remaining = 0 }
    }

    private func crackle() {
        guard let slot = crackles.firstIndex(where: { $0.remaining <= 0 }) else { return }
        let r = noise.uniform()
        let gain = 0.04 + r * r * r * 0.28
        let length = 0.005 + noise.uniform() * 0.02
        crackles[slot].gain = gain
        crackles[slot].decay = pow(0.0005 / gain, 1 / (length * sr))
        crackles[slot].remaining = Int((length + 0.01) * sr)
    }

    func next() -> (Double, Double) {
        while t >= nextCrackle {
            crackle()
            nextCrackle += -log(1 - noise.uniform()) / 3
        }
        t += 1 / sr
        if counter == 0 { gains.read(controls) }
        counter = (counter + 1) & 255
        let g = gains.next()
        var cl = 0.0, cr = 0.0
        for i in crackles.indices where crackles[i].remaining > 0 {
            cl += noise.white() * crackles[i].gain
            cr += noise.white() * crackles[i].gain
            crackles[i].gain *= crackles[i].decay
            crackles[i].remaining -= 1
        }
        return (lowL.process(brownL.process(noise.white())) * 0.75 * g[0] + hpL.process(cl) * g[1],
                lowR.process(brownR.process(noise.white())) * 0.75 * g[0] + hpR.process(cr) * g[1])
    }
}

/// Slow overlapping chords. A new chord starts every 13 seconds and each lasts 18.
final class AmbientSound: MusicGenerator {
    private struct Pad { var start = -100.0; var phases = SIMD16<Double>(); var steps = SIMD16<Double>() }

    private static let chords: [[Double]] = [[50, 57, 62, 66, 69], [47, 54, 59, 62, 66], [43, 50, 57, 62, 66], [45, 52, 57, 61, 64]]
    private let sr: Double
    private var pads = [Pad](repeating: Pad(), count: 2)
    private var low: Biquad
    private var t = 0.0
    private var nextPad = 0.1
    private var chord = 0

    init(sampleRate: Double) {
        sr = sampleRate
        low = Biquad(.lowpass, frequency: 850, sampleRate: sampleRate)
    }

    func reset() {
        t = 0; nextPad = 0.1; chord = 0
        for i in pads.indices { pads[i].start = -100 }
    }

    private func startPad(at time: Double) {
        let slot = pads[0].start <= pads[1].start ? 0 : 1
        let notes = Self.chords[chord % Self.chords.count]
        chord += 1
        pads[slot].start = time
        pads[slot].phases = SIMD16<Double>()
        for (i, n) in notes.enumerated() {
            // A sine slightly flat and a triangle slightly sharp for each note, as in app.js.
            pads[slot].steps[i] = midiToHz(n) * pow(2, -3.0 / 1200) / sr
            pads[slot].steps[i + 5] = midiToHz(n) * pow(2, 3.0 / 1200) / sr
        }
    }

    @inline(__always) private static func envelope(_ x: Double) -> Double {
        if x < 0 || x >= 18 { return 0 }
        if x < 6 { return 0.075 * x / 6 }
        if x < 10 { return 0.075 }
        return 0.075 * (18 - x) / 8
    }

    func next() -> (Double, Double) {
        while t >= nextPad {
            startPad(at: nextPad)
            nextPad += 13
        }
        var s = 0.0
        for p in pads.indices {
            let env = Self.envelope(t - pads[p].start)
            if env == 0 { continue }
            var sum = 0.0
            for k in 0..<5 {
                sum += sine(pads[p].phases[k]) + triangle(pads[p].phases[k + 5])
                pads[p].phases[k] = wrap(pads[p].phases[k] + pads[p].steps[k])
                pads[p].phases[k + 5] = wrap(pads[p].phases[k + 5] + pads[p].steps[k + 5])
            }
            s += sum * env
        }
        t += 1 / sr
        let out = low.process(s)
        return (out, out)
    }
}

/// A simple generated piano sketch: a low note every 6 seconds with a few soft notes above it.
final class SoftKeysSound: MusicGenerator {
    private struct Key {
        var start = -100.0
        var level = 0.0
        var env = 0.0
        var decay = 1.0
        var decaying = false
        var phases = SIMD4<Double>()
        var steps = SIMD4<Double>()
    }

    private static let chords: [[Double]] = [[50, 60, 64, 65, 69], [43, 59, 64, 65, 69], [48, 59, 62, 64, 67], [45, 60, 64, 67, 71]]
    private static let offsets: [Double] = [0.75, 1.5, 2.25, 3, 3.75, 4.5]
    private let sr: Double
    private var noise = Noise(seed: 0x6E75)
    private var keys = [Key](repeating: Key(), count: 16)
    private var low: Biquad
    private var t = 0.0
    private var nextChord = 0.1
    private var chord = 0

    init(sampleRate: Double) {
        sr = sampleRate
        low = Biquad(.lowpass, frequency: 1700, sampleRate: sampleRate)
    }

    func reset() {
        t = 0; nextChord = 0.1; chord = 0
        for i in keys.indices { keys[i].start = -100 }
    }

    private func press(_ note: Double, at time: Double, level: Double) {
        // Use a free key, or take over the one that started longest ago.
        var slot = 0
        for i in keys.indices where keys[i].start < keys[slot].start { slot = i }
        let f = midiToHz(note)
        keys[slot] = Key(start: time, level: level, env: 0, decay: pow(0.0005 / level, 1 / ((3.6 - 0.015) * sr)),
                         decaying: false, phases: SIMD4<Double>(), steps: SIMD4<Double>(f / sr, 2 * f / sr, 3 * f / sr, 0))
    }

    func next() -> (Double, Double) {
        while t >= nextChord {
            let c = Self.chords[chord % Self.chords.count]
            chord += 1
            press(c[0], at: nextChord, level: 0.16)
            for off in Self.offsets where noise.uniform() < 0.65 {
                let pick = c[1 + min(3, Int(noise.uniform() * 4))] + 12
                press(pick, at: nextChord + off + noise.uniform() * 0.03, level: 0.055 + noise.uniform() * 0.03)
            }
            nextChord += 6
        }
        var s = 0.0
        for i in keys.indices {
            let age = t - keys[i].start
            if age < 0 || age > 3.7 { continue }
            if age < 0.015 {
                keys[i].env = keys[i].level * age / 0.015
            } else {
                if !keys[i].decaying { keys[i].decaying = true; keys[i].env = keys[i].level }
                keys[i].env *= keys[i].decay
            }
            let p = keys[i].phases
            s += (sine(p[0]) + 0.16 * sine(p[1]) + 0.05 * sine(p[2])) * keys[i].env
            keys[i].phases = SIMD4<Double>(wrap(p[0] + keys[i].steps[0]), wrap(p[1] + keys[i].steps[1]), wrap(p[2] + keys[i].steps[2]), 0)
        }
        t += 1 / sr
        let out = low.process(s)
        return (out, out)
    }
}
