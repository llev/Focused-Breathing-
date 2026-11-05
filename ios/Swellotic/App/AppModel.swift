import SwiftUI

/// Connects the screen to the sound. Holds the settings, starts and stops sessions, and tells the visuals where the breath is.
@MainActor
final class AppModel: ObservableObject {
    @Published var settings: Settings {
        didSet { settingsChanged(from: oldValue) }
    }
    @Published private(set) var running = false
    @Published private(set) var status = "Press play to begin."
    @Published private(set) var showResume = false
    /// The session button's text: the session's settings when stopped, and its clock while playing.
    @Published private(set) var sessionText = ""
    @Published private(set) var resting = false
    /// The Classical mix piece's time, such as "1:23 / 9:05".
    @Published private(set) var pieceTime = ""

    let audio = AudioController()
    /// While nothing plays, the visuals follow a preview of the same timeline on the wall clock.
    private var preview: BreathTimeline
    private var ticker: Task<Void, Never>?
    private var resumeCheck: Task<Void, Never>?

    init() {
        let saved = Settings.load()
        settings = saved
        preview = BreathTimeline(startingAt: AudioController.hostNow(), pacing: Self.previewPacing(saved))
        audio.apply(saved)
        audio.onEvent = { [weak self] event in self?.handle(event) }
        audio.library.resumeSaving(saved.saveAll)
        sessionText = Self.summary(saved)
    }

    var library: ClassicalLibrary { audio.library }

    /// What the session button says while nothing plays.
    private static func summary(_ s: Settings) -> String {
        if s.mode == .interval {
            return "Swell \(s.swellMinutes) · Rest \(s.restMinutes) min" + (s.rounds > 0 ? " · \(s.rounds) rounds" : "")
        }
        return s.limitMinutes > 0 ? "\(s.limitMinutes) min timer" : "No time limit"
    }

    private static func clock(_ seconds: Double) -> String {
        let s = Int(max(0, seconds))
        return String(format: "%02d:%02d", s / 60, s % 60)
    }

    var tint: Color { settings.palette.tint }

    private static func previewPacing(_ s: Settings) -> Pacing {
        Pacing(bpm: s.bpm, inhaleShare: s.pattern.inhaleShare, ease: false, sessionStart: nil)
    }

    private func settingsChanged(from old: Settings) {
        guard settings != old else { return }
        settings.save()
        audio.apply(settings)
        if !running && (old.bpm != settings.bpm || old.pattern != settings.pattern) { resetPreview() }
        if running && old.track != settings.track { status = "" }
        if !running { sessionText = Self.summary(settings) }
    }

    private func resetPreview() {
        preview = BreathTimeline(startingAt: AudioController.hostNow(), pacing: Self.previewPacing(settings))
    }

    /// Where the breath is right now. Sound and visuals read the same timeline, so they can't drift apart.
    func frame(at now: Double = AudioController.hostNow()) -> BreathFrame {
        if running, let live = audio.liveFrame(now: now) { return live }
        if running {
            // The first sound block hasn't arrived yet: rest at the start of an in-breath.
            let p = BreathPhase(isIn: true, start: now, end: now + 1, bpm: settings.bpm)
            return BreathFrame(phase: p, time: now, level: 0)
        }
        preview.advance(to: now, pacing: Self.previewPacing(settings))
        return BreathFrame(phase: preview.current, time: now, level: preview.current.level(at: now))
    }

    // MARK: Playing

    func toggle() { running ? stop() : start() }

    func start() {
        guard !running else { return }
        do {
            try audio.start()
        } catch {
            status = "Sound couldn't start. Close Swellotic and open it again."
            return
        }
        running = true
        showResume = false
        resting = false
        status = ""
        sessionText = settings.mode == .interval ? "Swell \(Self.clock(Double(settings.swellMinutes * 60)))"
            : settings.sessionLength > 0 ? "\(Self.clock(settings.sessionLength)) left" : Self.clock(0)
        startTicker()
    }

    func stop(message: String? = nil) {
        guard running else { return }
        audio.stop()
        running = false
        showResume = false
        resting = false
        pieceTime = ""
        sessionText = Self.summary(settings)
        ticker?.cancel()
        resumeCheck?.cancel()
        status = message ?? "Press play to begin."
        resetPreview()
    }

    /// A tap counts as permission to play, which iOS needs before sound can restart after some interruptions.
    func tapToResume() {
        if audio.resume() {
            showResume = false
        } else {
            status = "Sound couldn't restart. Press stop, then play."
        }
    }

    /// The session clock, swell and rest, and the time limit. Runs while playing, including in the background.
    private func startTicker() {
        ticker?.cancel()
        ticker = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(50))
                self?.tick()
            }
        }
    }

    private func tick() {
        guard running else { return }
        if settings.track == .classical, let p = audio.piecePosition() {
            let text = "\(Self.pieceClock(p.now)) / \(Self.pieceClock(p.length))"
            if text != pieceTime { pieceTime = text }
        }
        guard let live = audio.liveFrame() else { return }
        let elapsed = live.time
        // The sound engine fades for rests on its own clock; this keeps the screen and the classical piece in step.
        let segment = settings.mode == .interval ? settings.plan.segment(at: elapsed) : (resting: false, left: 0)
        if segment.resting != resting {
            resting = segment.resting
            audio.setResting(resting)
            status = resting ? "Time for a break. The next swell starts by itself." : ""
        }
        let length = settings.sessionLength
        let text = settings.mode == .interval ? "\(resting ? "Rest" : "Swell") \(Self.clock(segment.left))"
            : length > 0 ? "\(Self.clock(max(0, length - elapsed))) left" : Self.clock(elapsed)
        if text != sessionText { sessionText = text }
        if length > 0 && elapsed >= length { stop(message: "Session finished.") }
    }

    private static func pieceClock(_ seconds: Double) -> String {
        let s = Int(max(0, seconds))
        return "\(s / 60):" + String(format: "%02d", s % 60)
    }

    private func handle(_ event: AudioController.Event) {
        switch event {
        case .paused:
            break
        case .resumed:
            showResume = false
            resumeCheck?.cancel()
        case .needsTap:
            if running { showResume = true }
        case .headphonesGone:
            stop(message: "Headphones disconnected, so Swellotic stopped.")
        case .remoteToggle:
            toggle()
        case .remotePlay:
            start()
        case .remotePause:
            stop()
        case .pieceChanged(let index):
            if settings.piece != index { settings.piece = index }
        case .classical(let message):
            if running { status = message ?? (resting ? status : "") }
        }
    }

    /// When Swellotic comes back on screen, restart the sound if the phone paused it.
    func scenePhaseChanged(_ phase: ScenePhase) {
        guard phase == .active, running, !audio.engineRunning else { return }
        if audio.resume() { return }
        resumeCheck?.cancel()
        resumeCheck = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(1500))
            guard let self, !Task.isCancelled, self.running, !self.audio.engineRunning else { return }
            self.showResume = true
        }
    }

    // MARK: Classical mix

    func skipPiece(_ step: Int) {
        let next = audio.skip(step)
        pieceTime = ""
        if settings.piece != next { settings.piece = next }
    }
}
