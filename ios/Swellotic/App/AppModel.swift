import SwiftUI
import UIKit

/// Connects the screen to the sound. Holds the settings, starts and stops sessions, and tells the visuals where the breath is.
@MainActor
final class AppModel: ObservableObject {
    @Published var settings: Settings {
        didSet { settingsChanged(from: oldValue) }
    }
    @Published private(set) var running = false
    @Published private(set) var status = "Press play to begin."
    @Published private(set) var showResume = false
    @Published private(set) var elapsed = "00:00"
    @Published private(set) var fileNames: [String] = []

    let audio = AudioController()
    /// While nothing plays, the visuals follow a preview of the same timeline on the wall clock.
    private var preview: BreathTimeline
    private var ticker: Task<Void, Never>?
    private var resumeCheck: Task<Void, Never>?
    private var lastTapped = -1.0
    private var onScreen = true
    private let haptic = UIImpactFeedbackGenerator(style: .soft)

    init() {
        let saved = Settings.load()
        settings = saved
        preview = BreathTimeline(startingAt: AudioController.hostNow(), pacing: Self.previewPacing(saved))
        audio.apply(saved)
        audio.onEvent = { [weak self] event in self?.handle(event) }
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
        if running && old.track != settings.track {
            status = settings.track == .files && fileNames.isEmpty ? "Add audio files to hear your music." : ""
        }
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
        elapsed = "00:00"
        lastTapped = -1
        status = settings.track == .files && fileNames.isEmpty ? "Add audio files to hear your music." : ""
        if settings.haptics { haptic.prepare() }
        startTicker()
    }

    func stop(message: String? = nil) {
        guard running else { return }
        audio.stop()
        running = false
        showResume = false
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

    /// The clock, the time limit and the breath taps. Runs while playing, including in the background.
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
        guard running, let live = audio.liveFrame() else { return }
        let seconds = Int(max(0, live.time))
        let text = String(format: "%02d:%02d", seconds / 60, seconds % 60)
        if text != elapsed { elapsed = text }
        if settings.limit > 0 && live.time >= Double(settings.limit * 60) {
            stop(message: "Session finished.")
            return
        }
        // A gentle tap as each breath turns. iOS only allows this while Swellotic is on screen.
        if live.time >= live.phase.start && live.phase.start != lastTapped {
            lastTapped = live.phase.start
            if settings.haptics && onScreen {
                haptic.impactOccurred(intensity: live.phase.isIn ? 0.8 : 0.5)
                haptic.prepare()
            }
        }
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
        }
    }

    /// When Swellotic comes back on screen, restart the sound if the phone paused it.
    func scenePhaseChanged(_ phase: ScenePhase) {
        onScreen = phase == .active
        guard phase == .active, running, !audio.engineRunning else { return }
        if audio.resume() { return }
        resumeCheck?.cancel()
        resumeCheck = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(1500))
            guard let self, !Task.isCancelled, self.running, !self.audio.engineRunning else { return }
            self.showResume = true
        }
    }

    // MARK: Audio files

    func addFiles(_ urls: [URL]) {
        Task {
            for url in urls {
                let label = url.lastPathComponent
                status = "Loading \(label)…"
                do {
                    fileNames.append(try await audio.addFile(url))
                } catch {
                    status = "\(label) couldn't be read. Try an MP3, M4A or WAV file."
                    return
                }
            }
            status = running ? "" : "Press play to begin."
        }
    }
}
