import Foundation
import Synchronization

/// A Double that the screen and the audio thread can share without locks.
final class AtomicDouble: Sendable {
    private let bits: Atomic<UInt64>
    init(_ value: Double) { bits = Atomic(value.bitPattern) }
    var value: Double { Double(bitPattern: bits.load(ordering: .relaxed)) }
    func set(_ value: Double) { bits.store(value.bitPattern, ordering: .relaxed) }
}

/// Settings written by the screen and read by the audio thread at the start of each block.
final class SynthControls: Sendable {
    let bpm = AtomicDouble(6)
    let inhaleShare = AtomicDouble(0.5)
    let ease = Atomic<Bool>(false)
    let cue = Atomic<Int>(BreathSound.bowl.rawValue)
    let track = Atomic<Int>(MusicTrack.brown.rawValue)
    let breathGain = AtomicDouble(0.11)
    let musicGain = AtomicDouble(0.3)
    /// Session number times two, plus one while playing. One value, so the audio thread never sees half a change.
    let state = Atomic<Int>(0)
    /// Goes up by one each time sound comes back after the phone paused it.
    let resumes = Atomic<Int>(0)

    var sessionID: Int { state.load(ordering: .relaxed) >> 1 }
    var isPlaying: Bool { state.load(ordering: .relaxed) & 1 == 1 }

    func begin() {
        let s = state.load(ordering: .relaxed)
        state.store((((s >> 1) + 1) << 1) | 1, ordering: .releasing)
    }

    func end() {
        let s = state.load(ordering: .relaxed)
        state.store((s >> 1) << 1, ordering: .releasing)
    }

    func soundBack() { _ = resumes.add(1, ordering: .releasing) }
}

/// Where the timeline was at the start of the last audio block.
struct LiveSnapshot: Equatable, Sendable {
    var session: Int
    var phase: BreathPhase
    var renderedSeconds: Double
    var hostSeconds: Double
}

/// Passes the latest snapshot from the audio thread to the screen with a sequence lock, so reads are never torn.
final class SnapshotBox: Sendable {
    private let seq = Atomic<Int>(0)
    private let session = Atomic<Int>(0)
    private let isIn = Atomic<Bool>(true)
    private let start = AtomicDouble(0)
    private let end = AtomicDouble(0)
    private let bpm = AtomicDouble(0)
    private let rendered = AtomicDouble(0)
    private let host = AtomicDouble(0)

    func write(_ s: LiveSnapshot) {
        let n = seq.load(ordering: .relaxed)
        seq.store(n &+ 1, ordering: .relaxed)
        atomicMemoryFence(ordering: .releasing)
        session.store(s.session, ordering: .relaxed)
        isIn.store(s.phase.isIn, ordering: .relaxed)
        start.set(s.phase.start)
        end.set(s.phase.end)
        bpm.set(s.phase.bpm)
        rendered.set(s.renderedSeconds)
        host.set(s.hostSeconds)
        seq.store(n &+ 2, ordering: .releasing)
    }

    func read() -> LiveSnapshot? {
        for _ in 0..<8 {
            let before = seq.load(ordering: .acquiring)
            if before == 0 { return nil }
            if before & 1 != 0 { continue }
            let s = LiveSnapshot(session: session.load(ordering: .relaxed),
                                 phase: BreathPhase(isIn: isIn.load(ordering: .relaxed), start: start.value, end: end.value, bpm: bpm.value),
                                 renderedSeconds: rendered.value, hostSeconds: host.value)
            atomicMemoryFence(ordering: .acquiring)
            if seq.load(ordering: .relaxed) == before { return s }
        }
        return nil
    }
}

/// All of Swellotic's sound. The breath half owns the timeline and plays a breath sound as each phase begins,
/// so timing is exact to the sample and keeps going when the screen is locked.
/// Call the render functions only from the audio thread, and the other functions only from the main thread.
final class SynthEngine: @unchecked Sendable {
    let controls: SynthControls
    let snapshot = SnapshotBox()
    private(set) var sampleRate: Double

    // Audio thread state
    private var frame: Int64 = 0
    private var live = false
    private var started = false
    private var seenSession = 0
    private var seenResume = 0
    private var nextStartFrame: Int64 = 0
    private var timeline = BreathTimeline(startingAt: 0.3, pacing: Pacing())
    private var voices = [CueVoice](repeating: CueVoice(), count: 4)
    private var lastCue: BreathSound = .bowl
    private var level: Smoother
    private var fade = Fade()
    private var music: MusicSynth

    /// The first breath begins this long after pressing play.
    static let leadIn = 0.3

    init(sampleRate: Double) {
        let controls = SynthControls()
        self.controls = controls
        self.sampleRate = sampleRate
        level = Smoother(value: 0, timeConstant: 0.05, sampleRate: sampleRate)
        music = MusicSynth(controls: controls, sampleRate: sampleRate)
    }

    /// Changes the sample rate. Only call this while the audio engine is stopped.
    func retune(sampleRate newRate: Double) {
        guard newRate > 0, newRate != sampleRate else { return }
        let ratio = newRate / sampleRate
        sampleRate = newRate
        frame = Int64((Double(frame) * ratio).rounded())
        nextStartFrame = frameIndex(started ? timeline.current.end : Self.leadIn)
        for i in voices.indices { voices[i].active = false }
        level = Smoother(value: level.value, timeConstant: 0.05, sampleRate: newRate)
        fade.jump(to: live ? 1 : 0)
        music.retune(sampleRate: newRate)
    }

    @inline(__always) private func frameIndex(_ seconds: Double) -> Int64 { Int64((seconds * sampleRate).rounded()) }

    private func pacing() -> Pacing {
        Pacing(bpm: controls.bpm.value, inhaleShare: controls.inhaleShare.value,
               ease: controls.ease.load(ordering: .relaxed), sessionStart: 0)
    }

    private func pollState() {
        let state = controls.state.load(ordering: .acquiring)
        let id = state >> 1, playing = state & 1 == 1
        if playing && id != seenSession {
            seenSession = id
            beginSession()
        } else if !playing && live {
            live = false
            fade.glide(to: 0, timeConstant: 0.15, sampleRate: sampleRate)
        }
        let r = controls.resumes.load(ordering: .acquiring)
        if r != seenResume {
            seenResume = r
            if live { fade.jump(to: 0); fade.ramp(to: 1, seconds: 0.8, sampleRate: sampleRate) }
        }
    }

    private func beginSession() {
        live = true
        started = false
        frame = 0
        timeline = BreathTimeline(startingAt: Self.leadIn, pacing: pacing())
        nextStartFrame = frameIndex(Self.leadIn)
        for i in voices.indices { voices[i].active = false }
        lastCue = BreathSound(rawValue: controls.cue.load(ordering: .relaxed)) ?? .bowl
        level.value = controls.breathGain.value
        fade.jump(to: 0)
        fade.ramp(to: 1, seconds: 0.8, sampleRate: sampleRate)
    }

    private func startVoice(_ sound: BreathSound, isIn: Bool, at start: Int64, length: Double) {
        guard sound != .silent else { return }
        var slot = voices.firstIndex(where: { !$0.active })
        if slot == nil { slot = voices.firstIndex(where: { $0.isReleasing }) }
        voices[slot ?? 0].trigger(sound, isIn: isIn, start: start, length: length, sampleRate: sampleRate)
    }

    /// A new breath sound fades the old one out and takes over the current breath from now, as in app.js.
    private func switchCue(at now: Int64) {
        for i in voices.indices where voices[i].active { voices[i].beginRelease(at: now, sampleRate: sampleRate) }
        let p = timeline.current
        let t = Double(now) / sampleRate
        if p.end - t > 0.25 {
            let from = t + 0.03
            startVoice(lastCue, isIn: p.isIn, at: frameIndex(from), length: p.end - from - 0.002)
        }
    }

    /// Fills one block of breath sound. The right channel may be nil for a mono output.
    func renderBreath(frameCount n: Int, left: UnsafeMutablePointer<Float>, right: UnsafeMutablePointer<Float>?, hostSeconds: Double) {
        pollState()
        if !live && fade.isSilent {
            for i in 0..<n { left[i] = 0; right?[i] = 0 }
            return
        }
        let pace = pacing()
        let cue = BreathSound(rawValue: controls.cue.load(ordering: .relaxed)) ?? .bowl
        if cue != lastCue {
            lastCue = cue
            if live && started { switchCue(at: frame) }
        }
        let gain = controls.breathGain.value
        let blockStart = frame
        for i in 0..<n {
            let now = blockStart + Int64(i)
            if live && now >= nextStartFrame {
                if started {
                    timeline.advance(to: max(Double(now) / sampleRate, timeline.current.end), pacing: pace)
                } else {
                    started = true
                }
                let p = timeline.current
                startVoice(lastCue, isIn: p.isIn, at: now, length: p.duration - 0.002)
                nextStartFrame = frameIndex(p.end)
            }
            var s = 0.0
            for v in voices.indices where voices[v].active { s += voices[v].next(frame: now, sampleRate: sampleRate) }
            s *= level.next(toward: gain) * fade.next()
            let out = Float(s)
            left[i] = out
            right?[i] = out
        }
        frame = blockStart + Int64(n)
        snapshot.write(LiveSnapshot(session: seenSession, phase: timeline.current,
                                    renderedSeconds: Double(blockStart) / sampleRate, hostSeconds: hostSeconds))
    }

    /// Fills one block of generated music.
    func renderMusic(frameCount n: Int, left: UnsafeMutablePointer<Float>, right: UnsafeMutablePointer<Float>?) {
        music.render(frameCount: n, left: left, right: right)
    }
}

/// The generated music half, with a crossfade when the track changes.
final class MusicSynth {
    private let controls: SynthControls
    private var sampleRate: Double
    private var generators: [MusicGenerator?]
    private var current: MusicGenerator?
    private var previous: MusicGenerator?
    private var currentTrack = -1
    private var currentFade = Fade()
    private var previousFade = Fade()
    private var level: Smoother
    private var master = Fade()
    private var live = false
    private var seenSession = 0
    private var seenResume = 0

    init(controls: SynthControls, sampleRate: Double) {
        self.controls = controls
        self.sampleRate = sampleRate
        generators = MusicTrack.allCases.map { makeGenerator($0, sampleRate: sampleRate) }
        level = Smoother(value: 0, timeConstant: 0.05, sampleRate: sampleRate)
    }

    func retune(sampleRate newRate: Double) {
        sampleRate = newRate
        generators = MusicTrack.allCases.map { makeGenerator($0, sampleRate: newRate) }
        current = currentTrack >= 0 && currentTrack < generators.count ? generators[currentTrack] : nil
        current?.reset()
        previous = nil
        currentFade.jump(to: 1)
        level = Smoother(value: level.value, timeConstant: 0.05, sampleRate: newRate)
        master.jump(to: live ? 1 : 0)
    }

    private func pollState() {
        let state = controls.state.load(ordering: .acquiring)
        let id = state >> 1, playing = state & 1 == 1
        if playing && id != seenSession {
            seenSession = id
            live = true
            master.jump(to: 0)
            master.ramp(to: 1, seconds: 0.8, sampleRate: sampleRate)
            level.value = controls.musicGain.value
            currentTrack = -1 // Start the track afresh, fading in.
            previous = nil
        } else if !playing && live {
            live = false
            master.glide(to: 0, timeConstant: 0.15, sampleRate: sampleRate)
        }
        let r = controls.resumes.load(ordering: .acquiring)
        if r != seenResume {
            seenResume = r
            if live { master.jump(to: 0); master.ramp(to: 1, seconds: 0.8, sampleRate: sampleRate) }
        }
    }

    private func switchTrack(to track: Int) {
        if let old = current {
            previous = old
            previousFade.jump(to: currentFade.value)
            previousFade.glide(to: 0, timeConstant: 0.25, sampleRate: sampleRate)
        }
        currentTrack = track
        current = track >= 0 && track < generators.count ? generators[track] : nil
        if current === previous { previous = nil }
        current?.reset()
        currentFade.jump(to: 0)
        currentFade.ramp(to: 1, seconds: 1.2, sampleRate: sampleRate)
    }

    func render(frameCount n: Int, left: UnsafeMutablePointer<Float>, right: UnsafeMutablePointer<Float>?) {
        pollState()
        if !live && master.isSilent {
            for i in 0..<n { left[i] = 0; right?[i] = 0 }
            return
        }
        let track = controls.track.load(ordering: .relaxed)
        if track != currentTrack { switchTrack(to: track) }
        let gain = controls.musicGain.value
        for i in 0..<n {
            var l = 0.0, r = 0.0
            if let c = current {
                let s = c.next(), f = currentFade.next()
                l += s.0 * f; r += s.1 * f
            }
            if let p = previous {
                let s = p.next(), f = previousFade.next()
                l += s.0 * f; r += s.1 * f
            }
            let g = level.next(toward: gain) * master.next()
            left[i] = Float(l * g)
            right?[i] = Float(r * g)
        }
        if previous != nil && previousFade.isSilent { previous = nil }
    }
}
