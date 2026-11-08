import XCTest
@testable import SwellCore

/// These check the generated sound is safe and keeps time. Only a person can judge how it sounds, so ask Lloyd to listen.
final class SynthTests: XCTestCase {
    let rate = 48_000.0
    let block = 512

    func render(_ engine: SynthEngine, seconds: Double) -> (breath: [Float], music: [Float]) {
        renderSynth(engine, seconds: seconds, rate: rate, block: block)
    }

    func makeEngine(sound: BreathSound = .bowl, track: MusicTrack = .brown, bpm: Double = 6) -> SynthEngine {
        let engine = SynthEngine(sampleRate: rate)
        engine.controls.cue.store(sound.rawValue, ordering: .relaxed)
        engine.controls.track.store(track.rawValue, ordering: .relaxed)
        engine.controls.bpm.set(bpm)
        engine.controls.breathGain.set(1)
        engine.controls.musicGain.set(1)
        return engine
    }

    func peak(_ samples: ArraySlice<Float>) -> Float { samples.reduce(0) { max($0, abs($1)) } }

    func rms(_ samples: [Float]) -> Double {
        sqrt(samples.reduce(0) { $0 + Double($1) * Double($1) } / Double(max(1, samples.count)))
    }

    func testNothingPlaysBeforeStart() {
        let engine = makeEngine()
        let out = render(engine, seconds: 1)
        XCTAssertEqual(peak(out.breath[...]), 0)
        XCTAssertEqual(peak(out.music[...]), 0)
        XCTAssertNil(engine.snapshot.read())
    }

    func testEveryBreathSoundIsSafeAndFallsSilentAsTheNextBreathBegins() {
        for sound in BreathSound.allCases {
            let engine = makeEngine(sound: sound, track: .musicApp, bpm: 6)
            engine.controls.begin()
            let out = render(engine, seconds: 21).breath
            XCTAssertTrue(out.allSatisfy { $0.isFinite }, "\(sound) made an invalid sample")
            let loudest = peak(out[...])
            XCTAssertLessThan(loudest, 1, "\(sound) is too loud")
            if sound == .silent {
                XCTAssertEqual(loudest, 0)
                continue
            }
            XCTAssertGreaterThan(loudest, 0.01, "\(sound) is inaudible")
            // At 6 a minute with even breaths, each phase lasts 5 seconds after a 0.3 second lead-in.
            for k in 1...3 {
                let boundary = Int((SynthEngine.leadIn + 5 * Double(k)) * rate)
                let tail = out[(boundary - Int(0.002 * rate))..<boundary]
                XCTAssertLessThan(peak(tail), loudest * 0.02, "\(sound) is still sounding when breath \(k + 1) begins")
                let body = out[(boundary + Int(0.5 * rate))..<(boundary + Int(1.5 * rate))]
                XCTAssertGreaterThan(peak(body), 0, "\(sound) didn't play for breath \(k + 1)")
            }
        }
    }

    func testEveryTrackIsSafeAndAudible() {
        for track in MusicTrack.allCases {
            let engine = makeEngine(sound: .silent, track: track)
            if track.isLearned { publishTestSounds(engine.controls.sounds) }
            engine.controls.begin()
            let out = render(engine, seconds: track == .ambient || track == .keys || track == .park ? 15 : 6).music
            XCTAssertTrue(out.allSatisfy { $0.isFinite }, "\(track) made an invalid sample")
            XCTAssertLessThan(peak(out[...]), 2, "\(track) is far too loud before the limiter")
            if track.isGenerated {
                XCTAssertGreaterThan(rms(out), 0.001, "\(track) is inaudible")
            } else {
                XCTAssertEqual(peak(out[...]), 0, "\(track) isn't generated, so it should be silent here")
            }
        }
    }

    func testStoppingFadesToSilence() {
        let engine = makeEngine(sound: .gong, track: .rain)
        engine.controls.begin()
        _ = render(engine, seconds: 3)
        engine.controls.end()
        let out = render(engine, seconds: 2.5)
        let quiet = Int(2.3 * rate)
        XCTAssertLessThan(peak(out.breath[quiet...]), 1e-4)
        XCTAssertLessThan(peak(out.music[quiet...]), 1e-4)
    }

    func testChangingSoundMidBreathKeepsGoing() {
        let engine = makeEngine(sound: .bowl, track: .ambient)
        engine.controls.begin()
        _ = render(engine, seconds: 2)
        engine.controls.cue.store(BreathSound.ocean.rawValue, ordering: .relaxed)
        engine.controls.track.store(MusicTrack.keys.rawValue, ordering: .relaxed)
        let out = render(engine, seconds: 3)
        XCTAssertTrue(out.breath.allSatisfy { $0.isFinite })
        XCTAssertTrue(out.music.allSatisfy { $0.isFinite })
        XCTAssertGreaterThan(peak(out.breath[Int(0.5 * rate)...]), 0.001, "The new sound takes over the current breath")
    }

    func testSnapshotFollowsTheTimeline() {
        let engine = makeEngine(bpm: 6)
        engine.controls.begin()
        _ = render(engine, seconds: 6)
        let snap = try! XCTUnwrap(engine.snapshot.read())
        XCTAssertEqual(snap.session, 1)
        XCTAssertFalse(snap.phase.isIn, "At 6 seconds the out-breath has begun")
        XCTAssertEqual(snap.phase.start, 5.3, accuracy: 1e-6)
        XCTAssertEqual(snap.renderedSeconds, 6, accuracy: 0.02)
    }

    func testNewSessionStartsTheBreathAgain() {
        let engine = makeEngine(bpm: 6)
        engine.controls.begin()
        _ = render(engine, seconds: 7)
        engine.controls.end()
        engine.controls.begin()
        _ = render(engine, seconds: 1)
        let snap = try! XCTUnwrap(engine.snapshot.read())
        XCTAssertEqual(snap.session, 2)
        XCTAssertTrue(snap.phase.isIn)
        XCTAssertEqual(snap.renderedSeconds, 1, accuracy: 0.02)
    }

    func testSampleRateChangeKeepsTheBreath() {
        let engine = makeEngine(bpm: 6)
        engine.controls.begin()
        _ = render(engine, seconds: 2)
        engine.retune(sampleRate: 44_100)
        let snapBefore = try! XCTUnwrap(engine.snapshot.read())
        XCTAssertTrue(snapBefore.phase.isIn)
        var l = [Float](repeating: 0, count: 441)
        l.withUnsafeMutableBufferPointer { engine.renderBreath(frameCount: 441, left: $0.baseAddress!, right: nil, hostSeconds: 0) }
        let snapAfter = try! XCTUnwrap(engine.snapshot.read())
        XCTAssertEqual(snapAfter.renderedSeconds, 2, accuracy: 0.02)
        XCTAssertEqual(snapAfter.phase, snapBefore.phase)
    }
}

/// Renders `seconds` of breath and music sound and returns the left channels.
func renderSynth(_ engine: SynthEngine, seconds: Double, rate: Double, block: Int) -> (breath: [Float], music: [Float]) {
    let total = Int(seconds * rate)
    var breath = [Float](), music = [Float]()
    breath.reserveCapacity(total); music.reserveCapacity(total)
    var l = [Float](repeating: 0, count: block), r = [Float](repeating: 0, count: block)
    var done = 0
    while done < total {
        let n = min(block, total - done)
        l.withUnsafeMutableBufferPointer { lp in
            r.withUnsafeMutableBufferPointer { rp in
                engine.renderBreath(frameCount: n, left: lp.baseAddress!, right: rp.baseAddress!, hostSeconds: Double(done) / rate)
            }
        }
        breath.append(contentsOf: l[0..<n])
        l.withUnsafeMutableBufferPointer { lp in
            r.withUnsafeMutableBufferPointer { rp in
                engine.renderMusic(frameCount: n, left: lp.baseAddress!, right: rp.baseAddress!)
            }
        }
        music.append(contentsOf: l[0..<n])
        done += n
    }
    return (breath, music)
}
