import Foundation

// The learned moods, ported from startVoice() in app.js: Rain on the window, Night storm, Winter park and Wind on the hill,
// plus Green noise. The rain, wind, park and thunder are files decoded into the SoundBank; the thrush is sung live.
// Like the other generators, these allocate nothing after they're created. A layer whose file hasn't loaded yet stays
// silent, then fades in when it arrives.

/// Levels that sit the learned sounds alongside brown noise, as in app.js.
enum LearnedLevel {
    static let rain = 5.5, thunder = 5.3, wind = 1.5, park = 1.4 * 0.9, birds = 0.075
}

/// Reads a looping clip with linear interpolation, so any file rate plays at any output rate.
struct LoopPlayer {
    var position = 0.0

    @inline(__always) mutating func next(_ c: SoundBank.Clip, sampleRate: Double) -> (Double, Double) {
        let i = min(Int(position), c.frames - 1), f = position - Double(i)
        let j = i + 1 == c.frames ? 0 : i + 1
        let s = c.samples
        let l = (Double(s[2 * i]) * (1 - f) + Double(s[2 * j]) * f) * (1.0 / 32768)
        let r = (Double(s[2 * i + 1]) * (1 - f) + Double(s[2 * j + 1]) * f) * (1.0 / 32768)
        position += c.rate / sampleRate
        if position >= Double(c.frames) { position -= Double(c.frames) }
        return (l, r)
    }
}

/// One looping layer: waits for its file, then fades in from a random point in the loop.
struct LoopLayer {
    let slot: SoundBank.Slot
    let base: Double
    var clip: SoundBank.Clip?
    var player = LoopPlayer()
    var arrive = 0.0

    init(_ slot: SoundBank.Slot, base: Double) { self.slot = slot; self.base = base }

    /// Checks for the file now and then, not every sample.
    mutating func poll(_ bank: SoundBank, noise: inout Noise) {
        guard clip == nil, let c = bank.clip(slot) else { return }
        clip = c
        player.position = noise.uniform() * Double(c.frames - 1)
    }

    @inline(__always) mutating func next(sampleRate: Double) -> (Double, Double) {
        guard let c = clip else { return (0, 0) }
        if arrive < 1 { arrive = min(1, arrive + 2 / sampleRate) }
        let s = player.next(c, sampleRate: sampleRate)
        let g = base * arrive
        return (s.0 * g, s.1 * g)
    }
}

/// Each sound's Mix sliders, eased so a change never clicks.
struct LayerGains {
    private var current = SIMD8<Double>(repeating: 1)
    private var target = SIMD8<Double>(repeating: 1)
    private let coeff: Double

    init(sampleRate: Double) { coeff = 1 - exp(-1 / (0.05 * sampleRate)) }

    mutating func read(_ controls: SynthControls) {
        for i in 0..<SynthControls.layerCount { target[i] = controls.layer(i) }
    }

    mutating func snap() { current = target }

    @inline(__always) mutating func next() -> SIMD8<Double> {
        current += (target - current) * coeff
        return current
    }
}

/// Noise centred on the middle frequencies.
final class GreenNoiseSound: MusicGenerator {
    private var noise = Noise(seed: 0x6E)
    private var pinkL = PinkFilter(), pinkR = PinkFilter()
    private var bandL, bandR: Biquad
    init(sampleRate: Double) {
        let b = Biquad(.bandpass, frequency: 520, q: 0.55, sampleRate: sampleRate)
        bandL = b; bandR = b
    }
    func reset() {}
    func next() -> (Double, Double) {
        (bandL.process(pinkL.process(noise.white())) * 1.4, bandR.process(pinkR.process(noise.white())) * 1.4)
    }
}

/// Rain on the window and Night storm: glass taps, metal taps and rain outside, learned from a storm recording.
/// Night storm adds wind and thunder rolls, one at a time with 15 to 45 seconds of rain between them.
final class RainMoodSound: MusicGenerator {
    private let sr: Double
    private let controls: SynthControls
    private let storm: Bool
    private var noise = Noise(seed: 0x5A1)
    private var layers: [LoopLayer]
    private var gains: LayerGains
    private var counter = 0
    private var t = 0.0
    // Thunder
    private var roll: SoundBank.Clip?
    private var rollPosition = 0.0
    private var rollGain = 0.0
    private var nextRoll = 4.0

    init(sampleRate: Double, controls: SynthControls, storm: Bool) {
        sr = sampleRate
        self.controls = controls
        self.storm = storm
        var l = [LoopLayer(.glass, base: LearnedLevel.rain), LoopLayer(.metal, base: LearnedLevel.rain), LoopLayer(.outside, base: LearnedLevel.rain)]
        if storm { l.append(LoopLayer(.wind, base: LearnedLevel.wind)) }
        layers = l
        gains = LayerGains(sampleRate: sampleRate)
        gains.read(controls); gains.snap()
    }

    func reset() {
        t = 0; counter = 0; roll = nil
        nextRoll = 3 + noise.uniform() * 3
        gains.read(controls); gains.snap()
    }

    private func startRoll() {
        var choices = 0
        for slot in SoundBank.Slot.thunder where controls.sounds.isReady(slot) { choices += 1 }
        guard choices > 0 else { nextRoll = t + 1; return } // Not loaded yet: try again in a second.
        var pick = Int(noise.uniform() * Double(choices))
        for slot in SoundBank.Slot.thunder {
            guard let c = controls.sounds.clip(slot) else { continue }
            if pick == 0 {
                roll = c; rollPosition = 0; rollGain = 0.6 + noise.uniform() * 0.4
                nextRoll = t + Double(c.frames) / c.rate + 15 + noise.uniform() * 30
                return
            }
            pick -= 1
        }
    }

    func next() -> (Double, Double) {
        if counter == 0 {
            gains.read(controls)
            for i in layers.indices { layers[i].poll(controls.sounds, noise: &noise) }
        }
        counter = (counter + 1) & 255
        let g = gains.next()
        var l = 0.0, r = 0.0
        for i in layers.indices {
            // Layers 0 to 2 are the rain; the wind is layer 4, after the thunder.
            let s = layers[i].next(sampleRate: sr), k = g[i < 3 ? i : 4]
            l += s.0 * k; r += s.1 * k
        }
        if storm {
            if roll == nil && t >= nextRoll { startRoll() }
            if let c = roll {
                let i = Int(rollPosition)
                if i >= c.frames - 1 {
                    roll = nil
                } else {
                    let f = rollPosition - Double(i), s = c.samples
                    let k = rollGain * LearnedLevel.thunder * g[3] * (1.0 / 32768)
                    l += (Double(s[2 * i]) * (1 - f) + Double(s[2 * i + 2]) * f) * k
                    r += (Double(s[2 * i + 1]) * (1 - f) + Double(s[2 * i + 3]) * f) * k
                    rollPosition += c.rate / sr
                }
            }
        }
        t += 1 / sr
        return (l, r)
    }
}

/// Wind on the hill: slow, uneven gusts, made in advance as a loop.
final class WindHillSound: MusicGenerator {
    private let sr: Double
    private let controls: SynthControls
    private var noise = Noise(seed: 0x417)
    private var wind = LoopLayer(.wind, base: LearnedLevel.wind)
    private var counter = 0

    init(sampleRate: Double, controls: SynthControls) { sr = sampleRate; self.controls = controls }
    func reset() {}
    func next() -> (Double, Double) {
        if counter == 0 { wind.poll(controls.sounds, noise: &noise) }
        counter = (counter + 1) & 255
        return wind.next(sampleRate: sr)
    }
}

/// Winter park: a park's hush learned from a recording, with a song thrush sung live from traced phrases.
final class ParkSound: MusicGenerator {
    private let sr: Double
    private let controls: SynthControls
    private var noise = Noise(seed: 0x9A4)
    private var park = LoopLayer(.park, base: LearnedLevel.park)
    private var thrush: ThrushSinger
    private var gains: LayerGains
    private var counter = 0

    init(sampleRate: Double, controls: SynthControls) {
        sr = sampleRate
        self.controls = controls
        thrush = ThrushSinger(sampleRate: sampleRate, spacing: 0.9, level: LearnedLevel.birds)
        gains = LayerGains(sampleRate: sampleRate)
        gains.read(controls); gains.snap()
    }

    func reset() { thrush.reset(); gains.read(controls); gains.snap() }

    func next() -> (Double, Double) {
        if counter == 0 {
            gains.read(controls)
            park.poll(controls.sounds, noise: &noise)
        }
        counter = (counter + 1) & 255
        let g = gains.next()
        let p = park.next(sampleRate: sr)
        let b = controls.sounds.thrush().map { thrush.next(song: $0) } ?? (0, 0)
        return (p.0 * g[0] + b.0 * g[1], p.1 * g[0] + b.1 * g[1])
    }
}

/// Sings a thrush's phrases with a tone and two soft overtones, in a new order each time, with a short echo.
final class ThrushSinger {
    private struct Voice {
        var active = false
        var note = 0
        var start = 0.0
        var phase = SIMD3<Double>()
        var weights = SIMD3<Double>()
        var left = 0.0, right = 0.0
    }

    private let sr: Double
    private let spacing: Double
    private let level: Double
    private var noise = Noise(seed: 0x7A8)
    private var voices = [Voice](repeating: Voice(), count: 16)
    private var t = 0.0
    private var nextPhrase = 1.5
    private var phrase = -1
    private var phraseStart = 0.0
    private var nextNote = 0
    private var lastNote = 0
    private var panLeft = 0.7, panRight = 0.7
    // Echo: a short delay, softened and fed back, as in app.js.
    private let echo: UnsafeMutablePointer<Double>
    private let echoLength: Int
    private var echoIndex = 0
    private var echoDelay: Int
    private var soften: Biquad

    init(sampleRate: Double, spacing: Double, level: Double) {
        sr = sampleRate
        self.spacing = spacing
        self.level = level
        echoLength = Int(sampleRate) + 1
        echo = .allocate(capacity: echoLength)
        echo.initialize(repeating: 0, count: echoLength)
        echoDelay = Int(0.19 * sampleRate)
        soften = Biquad(.lowpass, frequency: 4500, sampleRate: sampleRate)
    }

    deinit { echo.deallocate() }

    func reset() {
        t = 0; nextPhrase = 1 + noise.uniform() * 2; phrase = -1
        for i in voices.indices { voices[i].active = false }
        echo.update(repeating: 0, count: echoLength)
    }

    private func startPhrase(_ song: ThrushSong) {
        phrase = min(song.phraseCount - 1, Int(noise.uniform() * Double(song.phraseCount)))
        phraseStart = t
        nextNote = song.phraseFirst[phrase]
        lastNote = nextNote + song.phraseNotes[phrase]
        // Equal-power pan, somewhere between a little left and a little right.
        let pan = noise.uniform() * 0.8 - 0.4, angle = (pan + 1) * Double.pi / 4
        panLeft = cos(angle); panRight = sin(angle)
        var end = 0.0
        for n in nextNote..<lastNote { end = max(end, song.noteStart[n] + Double(song.notePoints[n]) * song.step) }
        let gap = max(0.3, song.gaps[min(song.gapCount - 1, Int(noise.uniform() * Double(song.gapCount)))])
        nextPhrase = t + end + gap * spacing * (0.7 + noise.uniform() * 0.8)
    }

    private func startNote(_ song: ThrushSong, _ n: Int) {
        guard let slot = voices.firstIndex(where: { !$0.active }) else { return }
        let f = song.pitch[song.noteFirstPoint[n]]
        var w = SIMD3<Double>(1, song.harmonic2[n], song.harmonic3[n])
        for k in 1..<3 where w[k] < 0.04 || f * Double(k + 1) > 15000 { w[k] = 0 }
        voices[slot] = Voice(active: true, note: n, start: phraseStart + song.noteStart[n], phase: SIMD3<Double>(), weights: w,
                             left: panLeft, right: panRight)
    }

    func next(song: ThrushSong) -> (Double, Double) {
        if t >= nextPhrase { startPhrase(song) }
        while phrase >= 0 && nextNote < lastNote && phraseStart + song.noteStart[nextNote] <= t {
            startNote(song, nextNote)
            nextNote += 1
        }
        var l = 0.0, r = 0.0
        for i in voices.indices where voices[i].active {
            let n = voices[i].note, d = song.notePoints[n], first = song.noteFirstPoint[n]
            let x = (t - voices[i].start) / song.step
            if x >= Double(d + 1) { voices[i].active = false; continue }
            // Pitch follows the traced points; loudness rises from and falls to silence around them.
            let xf = min(max(x, 0), Double(d - 1)), pi = min(Int(xf), d - 2), pf = xf - Double(pi)
            let f = song.pitch[first + pi] * (1 - pf) + song.pitch[first + pi + 1] * pf
            let u = x * Double(d + 1) / Double(d + 2), ai = Int(u), af = u - Double(ai)
            let a0 = ai == 0 || ai > d ? 0 : song.loudness[first + ai - 1]
            let a1 = ai + 1 > d ? 0 : song.loudness[first + ai]
            let amp = (a0 * (1 - af) + a1 * af) * level
            let p = voices[i].phase, w = voices[i].weights
            let s = sine(p[0]) * w[0] + sine(p[1]) * w[1] + sine(p[2]) * w[2]
            voices[i].phase = SIMD3<Double>(wrap(p[0] + f / sr), wrap(p[1] + 2 * f / sr), wrap(p[2] + 3 * f / sr))
            l += s * amp * voices[i].left; r += s * amp * voices[i].right
        }
        let readAt = (echoIndex - echoDelay + echoLength) % echoLength
        let wet = soften.process(echo[readAt]) * 0.22
        echo[echoIndex] = (l + r) * 0.5 + wet
        echoIndex = (echoIndex + 1) % echoLength
        t += 1 / sr
        return (l + wet, r + wet)
    }
}
