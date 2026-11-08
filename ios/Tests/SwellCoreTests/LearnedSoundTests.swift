import XCTest
@testable import SwellCore

/// Fills every slot with a quiet two-second tone, and the thrush with a tiny song, so the learned moods can be tested
/// without the real files. The tones are about as loud as the real rain layers, which are quiet files raised in level.
func publishTestSounds(_ bank: SoundBank) {
    let rate = 22_050.0, frames = Int(rate * 2)
    for slot in SoundBank.Slot.allCases {
        let p = UnsafeMutablePointer<Int16>.allocate(capacity: frames * 2)
        let hz = 200.0 + 60 * Double(slot.rawValue)
        for i in 0..<frames {
            let v = Int16(2000 * sin(2 * Double.pi * hz * Double(i) / rate))
            p[2 * i] = v; p[2 * i + 1] = v
        }
        bank.publish(slot, samples: p, frames: frames, rate: rate)
    }
    if let song = ThrushSong(json: testSong) { bank.publish(song) }
}

let testSong = Data("""
{"dt": 0.01, "phrases": [
  [[0, [3000, 3200, 3400], [-10, -6, -12], [0.1, 0.02]], [0.1, [2500, 2400], [-8, -9], [0, 0]]],
  [[0, [4000, 4100], [-6, -6], [0.05, 0]], [0.05, [3800, 3600, 3500], [-4, -5, -9], [0, 0]]],
  [[0, [5000, 5100], [-3, -3], [0, 0]]]
], "gaps": [0.5, 0.8]}
""".utf8)

final class LearnedSoundTests: XCTestCase {
    let rate = 48_000.0

    func testThrushSongKeepsOnlyRealPhrases() throws {
        let song = try XCTUnwrap(ThrushSong(json: testSong))
        XCTAssertEqual(song.phraseCount, 2, "The single-note phrase should be dropped")
        XCTAssertEqual(song.phraseNotes[0], 2)
        XCTAssertEqual(song.notePoints[0], 3)
        XCTAssertEqual(song.loudness[song.noteFirstPoint[3]], 1, accuracy: 1e-9, "The loudest point should be 1")
        XCTAssertEqual(song.gapCount, 2)
        XCTAssertNil(ThrushSong(json: Data("{}".utf8)))
    }

    func testBankPublishesOnce() {
        let bank = SoundBank()
        XCTAssertNil(bank.clip(.glass))
        let p = UnsafeMutablePointer<Int16>.allocate(capacity: 8)
        p.initialize(repeating: 1, count: 8)
        bank.publish(.glass, samples: p, frames: 4, rate: 44_100)
        XCTAssertTrue(bank.isReady(.glass))
        XCTAssertEqual(bank.clip(.glass)?.frames, 4)
        XCTAssertFalse(bank.isReady(.metal))
    }

    func testLearnedMoodsAreSilentUntilLoaded() {
        for track in MusicTrack.allCases where track.isLearned {
            let engine = SynthEngine(sampleRate: rate)
            engine.controls.track.store(track.rawValue, ordering: .relaxed)
            engine.controls.musicGain.set(1)
            engine.controls.begin()
            let out = renderSynth(engine, seconds: 2, rate: rate, block: 512).music
            XCTAssertEqual(out.reduce(0) { max($0, abs($1)) }, 0, "\(track) should wait for its files")
        }
    }

    func testMixSliderSilencesALayer() {
        func level(glass: Double) -> Double {
            let engine = SynthEngine(sampleRate: rate)
            publishTestSounds(engine.controls.sounds)
            engine.controls.track.store(MusicTrack.window.rawValue, ordering: .relaxed)
            engine.controls.musicGain.set(1)
            for i in 0..<SynthControls.layerCount { engine.controls.setLayer(i, i == 0 ? glass : 0) }
            engine.controls.begin()
            let out = renderSynth(engine, seconds: 3, rate: rate, block: 512).music.suffix(Int(rate))
            return sqrt(out.reduce(0) { $0 + Double($1) * Double($1) } / Double(out.count))
        }
        XCTAssertGreaterThan(level(glass: 1), 0.01)
        XCTAssertLessThan(level(glass: 0), 1e-4)
    }

    func testNightStormRollsThunder() {
        let engine = SynthEngine(sampleRate: rate)
        publishTestSounds(engine.controls.sounds)
        engine.controls.track.store(MusicTrack.storm.rawValue, ordering: .relaxed)
        engine.controls.musicGain.set(1)
        for i in 0..<SynthControls.layerCount { engine.controls.setLayer(i, i == SoundLayer.thunder.index ? 1 : 0) }
        engine.controls.begin()
        let out = renderSynth(engine, seconds: 8, rate: rate, block: 512).music
        XCTAssertTrue(out.allSatisfy { $0.isFinite })
        XCTAssertGreaterThan(out.reduce(0) { max($0, abs($1)) }, 0.01, "A thunder roll should start within the first six seconds")
    }
}
