import XCTest
@testable import SwellCore

final class IntervalTests: XCTestCase {
    func testSegmentsTakeTurns() {
        let plan = IntervalPlan(swell: 25 * 60, rest: 5 * 60)
        XCTAssertFalse(plan.segment(at: 0).resting)
        XCTAssertEqual(plan.segment(at: 60).left, 24 * 60, accuracy: 1e-9)
        XCTAssertTrue(plan.segment(at: 25 * 60).resting)
        XCTAssertEqual(plan.segment(at: 26 * 60).left, 4 * 60, accuracy: 1e-9)
        XCTAssertFalse(plan.segment(at: 30 * 60).resting, "The next swell follows the rest")
    }

    func testLengthEndsAfterTheLastSwell() {
        let plan = IntervalPlan(swell: 25, rest: 5)
        XCTAssertEqual(plan.length(rounds: 4), 4 * 25 + 3 * 5)
        XCTAssertEqual(plan.length(rounds: 0), 0, "Until I stop")
    }

    /// A short swell and rest so the test runs quickly: 2 seconds of swell, then 6 of rest.
    func testRestFadesSoundOutWithAChimeAndTheSwellBringsItBack() {
        let rate = 48_000.0
        let engine = SynthEngine(sampleRate: rate)
        let c = engine.controls
        c.cue.store(BreathSound.tone.rawValue, ordering: .relaxed)
        c.track.store(MusicTrack.brown.rawValue, ordering: .relaxed)
        c.breathGain.set(1); c.musicGain.set(1)
        c.interval.store(true, ordering: .relaxed)
        c.swellSeconds.set(2); c.restSeconds.set(6)
        c.begin()

        let out = renderSynth(engine, seconds: 10, rate: rate, block: 512)
        func peak(_ a: [Float], _ from: Double, _ to: Double) -> Float {
            a[Int(from * rate)..<Int(to * rate)].reduce(0) { max($0, abs($1)) }
        }
        XCTAssertGreaterThan(peak(out.music, 1, 2), 0.05, "Music plays during the swell")
        XCTAssertLessThan(peak(out.music, 6, 8), 0.01, "Music fades out during the rest")
        XCTAssertGreaterThan(peak(out.breath, 2.05, 2.5), 0.01, "A chime marks the rest")
        XCTAssertLessThan(peak(out.breath, 7, 8), 0.01, "The breath is quiet once the chime has faded")
        XCTAssertGreaterThan(peak(out.music, 9, 10), 0.05, "Music comes back for the next swell")
        XCTAssertTrue(out.breath.allSatisfy { $0.isFinite })
    }
}
