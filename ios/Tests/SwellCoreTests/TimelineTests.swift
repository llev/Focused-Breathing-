import XCTest
@testable import SwellCore

final class TimelineTests: XCTestCase {
    func testEvenBreathsAtSixAMinute() {
        let pacing = Pacing(bpm: 6, inhaleShare: 0.5)
        var timeline = BreathTimeline(startingAt: 0, pacing: pacing)
        XCTAssertEqual(timeline.current, BreathPhase(isIn: true, start: 0, end: 5, bpm: 6))
        XCTAssertFalse(timeline.advance(to: 4.9, pacing: pacing))
        XCTAssertTrue(timeline.advance(to: 5, pacing: pacing))
        XCTAssertEqual(timeline.current, BreathPhase(isIn: false, start: 5, end: 10, bpm: 6))
        timeline.advance(to: 10, pacing: pacing)
        XCTAssertEqual(timeline.current, BreathPhase(isIn: true, start: 10, end: 15, bpm: 6))
    }

    func testLongerOutBreath() {
        let pacing = Pacing(bpm: 6, inhaleShare: BreathPattern.long.inhaleShare)
        var timeline = BreathTimeline(startingAt: 0, pacing: pacing)
        XCTAssertEqual(timeline.current.duration, 4, accuracy: 1e-9)
        timeline.advance(to: 4, pacing: pacing)
        XCTAssertEqual(timeline.current.duration, 6, accuracy: 1e-9)
    }

    func testPhasesFollowOnWithNoGaps() {
        let pacing = Pacing(bpm: 7.5, inhaleShare: BreathPattern.longest.inhaleShare)
        var timeline = BreathTimeline(startingAt: 0.3, pacing: pacing)
        var last = timeline.current
        for _ in 0..<50 {
            timeline.advance(to: last.end, pacing: pacing)
            XCTAssertEqual(timeline.current.start, last.end, accuracy: 1e-9)
            XCTAssertNotEqual(timeline.current.isIn, last.isIn)
            last = timeline.current
        }
    }

    func testSpeedChangesApplyFromTheNextBreath() {
        var pacing = Pacing(bpm: 6)
        var timeline = BreathTimeline(startingAt: 0, pacing: pacing)
        timeline.advance(to: 2, pacing: pacing)
        pacing.bpm = 12
        timeline.advance(to: 5, pacing: pacing)
        XCTAssertEqual(timeline.current, BreathPhase(isIn: false, start: 5, end: 10, bpm: 6), "The breath already under way keeps its length")
        timeline.advance(to: 10, pacing: pacing)
        XCTAssertEqual(timeline.current, BreathPhase(isIn: true, start: 10, end: 12.5, bpm: 12))
    }

    func testSlowingDownGradually() {
        let pacing = Pacing(bpm: 6, inhaleShare: 0.5, ease: true, sessionStart: 0)
        XCTAssertEqual(pacing.pace(at: 0), 10)
        XCTAssertEqual(pacing.pace(at: 90), 8, accuracy: 1e-9)
        XCTAssertEqual(pacing.pace(at: 180), 6)
        XCTAssertEqual(pacing.pace(at: 600), 6)
        XCTAssertEqual(Pacing(bpm: 6, ease: true, sessionStart: nil).pace(at: 0), 6, "Previews don't slow down")
        XCTAssertEqual(Pacing(bpm: 11, ease: true, sessionStart: 0).pace(at: 0), 11, "Paces of 10 or more aren't eased")
    }

    func testLongGapStartsAfresh() {
        let pacing = Pacing(bpm: 6)
        var timeline = BreathTimeline(startingAt: 0, pacing: pacing)
        timeline.advance(to: 10_000, pacing: pacing)
        XCTAssertEqual(timeline.current.start, 10_000)
        XCTAssertTrue(timeline.current.isIn)
    }

    func testLevelRisesOnInAndFallsOnOut() {
        let inPhase = BreathPhase(isIn: true, start: 0, end: 4, bpm: 6)
        XCTAssertEqual(inPhase.level(at: 0), 0, accuracy: 1e-9)
        XCTAssertEqual(inPhase.level(at: 2), 0.5, accuracy: 1e-9)
        XCTAssertEqual(inPhase.level(at: 4), 1, accuracy: 1e-9)
        let outPhase = BreathPhase(isIn: false, start: 4, end: 10, bpm: 6)
        XCTAssertEqual(outPhase.level(at: 4), 1, accuracy: 1e-9)
        XCTAssertEqual(outPhase.level(at: 10), 0, accuracy: 1e-9)
        XCTAssertEqual(inPhase.level(at: -1), 0, "Before the first breath, the scene rests empty")
    }
}
