import AudioToolbox
import AVFoundation
import MediaPlayer
import UIKit

/// Runs Swellotic's sound on Apple's audio engine.
///
/// Signal path:
/// breath → sum → limiter → output
/// generated music + audio files → music mixer → room filter → room reverb → sum
///
/// The app asks iOS for background audio (UIBackgroundModes in Info.plist), so sound keeps playing when the screen locks.
/// "My music app" mixes with other apps, so Spotify or Apple Music keep playing; everything else takes over the sound.
/// The playback category means the silent switch doesn't mute the breaths.
@MainActor
final class AudioController {
    enum Event { case paused, resumed, needsTap, headphonesGone, remoteToggle, remotePlay, remotePause }

    var onEvent: ((Event) -> Void)?
    private(set) var synth = SynthEngine(sampleRate: 48_000)
    private(set) var isPlaying = false

    private var engine = AVAudioEngine()
    private var built = false
    private var format = AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 2)!
    /// Audio files are converted to this once, and the music mixer converts them to the output rate.
    private let fileFormat = AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 2)!
    private var breathNode: AVAudioSourceNode?
    private var musicNode: AVAudioSourceNode?
    private var musicMixer = AVAudioMixerNode()
    private var roomFilter = AVAudioUnitEQ(numberOfBands: 1)
    private var roomReverb = AVAudioUnitReverb()
    private var sum = AVAudioMixerNode()
    private var limiter = AudioController.makeLimiter()
    private var player = AVAudioPlayerNode()
    private let latency = AtomicDouble(0)

    private var settings = Settings()
    private var stopTask: Task<Void, Never>?
    private var rampTask: Task<Void, Never>?
    private var observers: [NSObjectProtocol] = []

    struct OwnTrack: Identifiable { let id = UUID(); let name: String; let buffer: AVAudioPCMBuffer }
    private(set) var ownTracks: [OwnTrack] = []
    private var fileRun = 0
    private var fileIndex = 0
    private var filesPlaying = false

    init() {
        _ = Self.hostTicksToSeconds
        observe()
        setUpRemoteCommands()
    }

    // MARK: Building the engine

    nonisolated private static let hostTicksToSeconds: Double = {
        var info = mach_timebase_info_data_t()
        mach_timebase_info(&info)
        return Double(info.numer) / Double(info.denom) / 1_000_000_000
    }()

    /// The current time on the same clock as the audio engine's timestamps.
    nonisolated static func hostNow() -> Double { Double(mach_absolute_time()) * hostTicksToSeconds }

    nonisolated private static func makeLimiter() -> AVAudioUnitEffect {
        AVAudioUnitEffect(audioComponentDescription: AudioComponentDescription(
            componentType: kAudioUnitType_Effect, componentSubType: kAudioUnitSubType_PeakLimiter,
            componentManufacturer: kAudioUnitManufacturer_Apple, componentFlags: 0, componentFlagsMask: 0))
    }

    /// The render callbacks run on the audio thread, so they're built outside the main actor and touch only the synth.
    nonisolated private static func makeSource(synth: SynthEngine, latency: AtomicDouble, format: AVAudioFormat, music: Bool) -> AVAudioSourceNode {
        let toSeconds = hostTicksToSeconds
        return AVAudioSourceNode(format: format) { _, timestamp, frameCount, bufferList -> OSStatus in
            let buffers = UnsafeMutableAudioBufferListPointer(bufferList)
            guard buffers.count > 0, let l = buffers[0].mData?.assumingMemoryBound(to: Float.self) else { return noErr }
            let r = buffers.count > 1 ? buffers[1].mData?.assumingMemoryBound(to: Float.self) : nil
            let n = Int(frameCount)
            if music {
                synth.renderMusic(frameCount: n, left: l, right: r)
            } else {
                let ts = timestamp.pointee
                let host = ts.mFlags.contains(.hostTimeValid)
                    ? Double(ts.mHostTime) * toSeconds
                    : Double(mach_absolute_time()) * toSeconds + latency.value
                synth.renderBreath(frameCount: n, left: l, right: r, hostSeconds: host)
            }
            return noErr
        }
    }

    private func outputSampleRate() -> Double {
        let engineRate = engine.outputNode.outputFormat(forBus: 0).sampleRate
        if engineRate > 0 { return engineRate }
        let sessionRate = AVAudioSession.sharedInstance().sampleRate
        return sessionRate > 0 ? sessionRate : 48_000
    }

    /// Builds a fresh engine. Used at first play, when the output's sample rate changes, and if iOS resets its media services.
    private func build() {
        engine.stop()
        engine = AVAudioEngine()
        musicMixer = AVAudioMixerNode()
        roomFilter = AVAudioUnitEQ(numberOfBands: 1)
        roomReverb = AVAudioUnitReverb()
        sum = AVAudioMixerNode()
        limiter = Self.makeLimiter()
        player = AVAudioPlayerNode()
        filesPlaying = false

        let rate = outputSampleRate()
        format = AVAudioFormat(standardFormatWithSampleRate: rate, channels: 2)!
        synth.retune(sampleRate: rate)
        let breath = Self.makeSource(synth: synth, latency: latency, format: format, music: false)
        let music = Self.makeSource(synth: synth, latency: latency, format: format, music: true)
        breathNode = breath
        musicNode = music

        for node in [breath, music, musicMixer, player, roomFilter, roomReverb, sum, limiter] as [AVAudioNode] { engine.attach(node) }
        engine.connect(breath, to: sum, format: format)
        engine.connect(music, to: musicMixer, format: format)
        engine.connect(player, to: musicMixer, format: fileFormat)
        engine.connect(musicMixer, to: roomFilter, format: format)
        engine.connect(roomFilter, to: roomReverb, format: format)
        engine.connect(roomReverb, to: sum, format: format)
        engine.connect(sum, to: limiter, format: format)
        engine.connect(limiter, to: engine.mainMixerNode, format: format)

        let band = roomFilter.bands[0]
        band.filterType = .lowPass
        band.frequency = 2200
        band.bypass = false
        roomReverb.loadFactoryPreset(.mediumHall)
        applyRoom()
        engine.prepare()
        built = true
    }

    // MARK: Settings

    func apply(_ new: Settings) {
        let old = settings
        settings = new
        let c = synth.controls
        c.bpm.set(new.bpm)
        c.inhaleShare.set(new.pattern.inhaleShare)
        c.ease.store(new.ease, ordering: .relaxed)
        c.cue.store(new.sound.rawValue, ordering: .relaxed)
        c.track.store(new.track.rawValue, ordering: .relaxed)
        // Music apps play mastered tracks close to full scale, so breaths get extra headroom alongside them.
        // The limiter catches any peaks.
        c.breathGain.set(volumeCurve(new.breathVolume) * 0.9 * (new.track == .musicApp ? Self.musicAppBoost : 1))
        c.musicGain.set(volumeCurve(new.musicVolume))
        if built { applyRoom() }
        if rampTask == nil && filesPlaying { player.volume = fileVolume }
        if isPlaying && old.lowerMusicApp != new.lowerMusicApp && new.track == .musicApp {
            configureSession()
            try? AVAudioSession.sharedInstance().setActive(true)
        }
        guard isPlaying, old.track != new.track else { return }
        configureSession()
        if new.track == .files { startFiles() } else if old.track == .files { stopFiles() }
        updateNowPlaying()
    }

    private var fileVolume: Float { Float(volumeCurve(settings.musicVolume)) }

    /// "Put music in the room" keeps the breath close and makes the music sound further away.
    private func applyRoom() {
        let on = settings.room && settings.track != .musicApp
        roomFilter.bands[0].bypass = !on
        roomReverb.bypass = !on
        roomReverb.wetDryMix = on ? 50 : 0
    }

    /// About 9.5 dB louder breaths with "My music app".
    static let musicAppBoost = 3.0

    /// "Lower my music app" asks iOS to duck other apps for the whole session. iOS sets how much, and it's a steady
    /// reduction, never one that follows the breath.
    private func configureSession() {
        let session = AVAudioSession.sharedInstance()
        var options: AVAudioSession.CategoryOptions = []
        if settings.track == .musicApp {
            options = settings.lowerMusicApp ? [.mixWithOthers, .duckOthers] : [.mixWithOthers]
        }
        if session.category != .playback || session.categoryOptions != options {
            try? session.setCategory(.playback, mode: .default, options: options)
        }
    }

    private func updateLatency() {
        let session = AVAudioSession.sharedInstance()
        latency.set(session.outputLatency + session.ioBufferDuration)
    }

    // MARK: Playing

    func start() throws {
        stopTask?.cancel()
        stopTask = nil
        configureSession()
        try AVAudioSession.sharedInstance().setActive(true)
        updateLatency()
        if !built || outputSampleRate() != format.sampleRate { build() }
        if !engine.isRunning { try engine.start() }
        synth.controls.begin()
        isPlaying = true
        if settings.track == .files { startFiles() }
        updateNowPlaying()
    }

    func stop() {
        synth.controls.end()
        isPlaying = false
        stopFiles()
        updateNowPlaying()
        // Let the fade finish, then release the sound so other apps can carry on.
        stopTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(700))
            guard let self, !Task.isCancelled, !self.isPlaying else { return }
            self.engine.pause()
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        }
    }

    var engineRunning: Bool { engine.isRunning }

    /// Restarts sound after the phone paused it. The breath carries on from where it stopped and fades in.
    @discardableResult
    func resume() -> Bool {
        guard isPlaying else { return false }
        do {
            configureSession()
            try AVAudioSession.sharedInstance().setActive(true)
            updateLatency()
            if !engine.isRunning { try engine.start() }
            synth.controls.soundBack()
            if settings.track == .files { startFiles() }
            onEvent?(.resumed)
            return true
        } catch {
            return false
        }
    }

    /// Where the breath is now, for the visuals. Nil when nothing is playing.
    func liveFrame(now: Double = AudioController.hostNow()) -> BreathFrame? {
        guard isPlaying, let s = synth.snapshot.read(), s.session == synth.controls.sessionID else { return nil }
        // The snapshot is from the start of the last block. Carry it forward, but not far, so a paused sound freezes the picture.
        let t = s.renderedSeconds + min(0.25, max(-0.5, now - s.hostSeconds))
        return BreathFrame(phase: s.phase, time: t, level: s.phase.level(at: t))
    }

    // MARK: Audio files

    /// Reads a file into memory in a standard format. It stays on the device and is never uploaded.
    nonisolated static func decode(_ url: URL, to format: AVAudioFormat) throws -> AVAudioPCMBuffer {
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        let file = try AVAudioFile(forReading: url)
        let inFormat = file.processingFormat
        guard file.length > 0, let input = AVAudioPCMBuffer(pcmFormat: inFormat, frameCapacity: AVAudioFrameCount(file.length)) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        try file.read(into: input)
        guard let converter = AVAudioConverter(from: inFormat, to: format) else { throw CocoaError(.fileReadCorruptFile) }
        if inFormat.channelCount == 1 { converter.channelMap = [0, 0] }
        let capacity = AVAudioFrameCount(Double(input.frameLength) * format.sampleRate / inFormat.sampleRate) + 4096
        guard let output = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: capacity) else { throw CocoaError(.fileReadCorruptFile) }
        var fed = false
        var error: NSError?
        let status = converter.convert(to: output, error: &error) { _, outStatus in
            if fed {
                outStatus.pointee = .endOfStream
                return nil
            }
            fed = true
            outStatus.pointee = .haveData
            return input
        }
        if let error { throw error }
        if status == .error || output.frameLength == 0 { throw CocoaError(.fileReadCorruptFile) }
        return output
    }

    func addFile(_ url: URL) async throws -> String {
        let format = fileFormat
        let box = try await Task.detached(priority: .userInitiated) { DecodedAudio(buffer: try AudioController.decode(url, to: format)) }.value
        let buffer = box.buffer
        let name = url.deletingPathExtension().lastPathComponent
        ownTracks.append(OwnTrack(name: name, buffer: buffer))
        if isPlaying && settings.track == .files { startFiles() }
        return name
    }

    private func startFiles() {
        guard built, !ownTracks.isEmpty else { return }
        fileRun += 1
        fileIndex = 0
        player.stop()
        player.volume = 0
        // Keep two files queued so they follow on without a gap.
        scheduleNextFile(run: fileRun)
        scheduleNextFile(run: fileRun)
        player.play()
        filesPlaying = true
        rampPlayer(to: fileVolume, seconds: 1.2)
    }

    private func scheduleNextFile(run: Int) {
        guard run == fileRun, !ownTracks.isEmpty else { return }
        let track = ownTracks[fileIndex % ownTracks.count]
        fileIndex += 1
        player.scheduleBuffer(track.buffer, completionCallbackType: .dataConsumed) { [weak self] _ in
            Task { @MainActor in self?.scheduleNextFile(run: run) }
        }
    }

    private func stopFiles() {
        guard filesPlaying else { return }
        fileRun += 1
        filesPlaying = false
        let run = fileRun
        rampPlayer(to: 0, seconds: 0.3) { [weak self] in
            guard let self, self.fileRun == run else { return }
            self.player.stop()
        }
    }

    private func rampPlayer(to target: Float, seconds: Double, then: (() -> Void)? = nil) {
        rampTask?.cancel()
        let from = player.volume
        let steps = max(1, Int(seconds / 0.02))
        rampTask = Task { [weak self] in
            for i in 1...steps {
                try? await Task.sleep(for: .milliseconds(20))
                guard let self, !Task.isCancelled else { return }
                self.player.volume = from + (target - from) * Float(i) / Float(steps)
            }
            self?.rampTask = nil
            then?()
        }
    }

    // MARK: Interruptions, headphones and the lock screen

    private func observe() {
        let centre = NotificationCenter.default
        observers.append(centre.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: .main) { [weak self] note in
            let info = note.userInfo ?? [:]
            let type = (info[AVAudioSessionInterruptionTypeKey] as? UInt).flatMap(AVAudioSession.InterruptionType.init(rawValue:))
            let options = AVAudioSession.InterruptionOptions(rawValue: info[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0)
            MainActor.assumeIsolated { self?.interrupted(type: type, shouldResume: options.contains(.shouldResume)) }
        })
        observers.append(centre.addObserver(forName: AVAudioSession.routeChangeNotification, object: nil, queue: .main) { [weak self] note in
            let raw = note.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt ?? 0
            let reason = AVAudioSession.RouteChangeReason(rawValue: raw)
            MainActor.assumeIsolated { self?.routeChanged(reason) }
        })
        observers.append(centre.addObserver(forName: .AVAudioEngineConfigurationChange, object: nil, queue: .main) { [weak self] note in
            let changed = note.object as? AVAudioEngine
            MainActor.assumeIsolated {
                guard let self, let changed, changed === self.engine else { return }
                self.engineChanged()
            }
        })
        observers.append(centre.addObserver(forName: AVAudioSession.mediaServicesWereResetNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.built = false
                if self.isPlaying {
                    self.build()
                    if !self.resume() { self.onEvent?(.needsTap) }
                }
            }
        })
    }

    private func interrupted(type: AVAudioSession.InterruptionType?, shouldResume: Bool) {
        guard isPlaying, let type else { return }
        switch type {
        case .began:
            onEvent?(.paused)
        case .ended:
            if !(shouldResume && resume()) { onEvent?(.needsTap) }
        @unknown default:
            break
        }
    }

    private func routeChanged(_ reason: AVAudioSession.RouteChangeReason?) {
        updateLatency()
        // Apple's guidance: when headphones are unplugged, pause rather than play out loud.
        if reason == .oldDeviceUnavailable && isPlaying { onEvent?(.headphonesGone) }
    }

    /// The output changed, for example to Bluetooth headphones. The engine stops itself, so start it again.
    private func engineChanged() {
        guard isPlaying else {
            if outputSampleRate() != format.sampleRate { built = false }
            return
        }
        if outputSampleRate() != format.sampleRate { build() }
        if !resume() { onEvent?(.needsTap) }
    }

    private func setUpRemoteCommands() {
        let centre = MPRemoteCommandCenter.shared()
        centre.playCommand.addTarget { [weak self] _ in
            MainActor.assumeIsolated { self?.onEvent?(.remotePlay) }
            return .success
        }
        centre.pauseCommand.addTarget { [weak self] _ in
            MainActor.assumeIsolated { self?.onEvent?(.remotePause) }
            return .success
        }
        centre.togglePlayPauseCommand.addTarget { [weak self] _ in
            MainActor.assumeIsolated { self?.onEvent?(.remoteToggle) }
            return .success
        }
        centre.stopCommand.addTarget { [weak self] _ in
            MainActor.assumeIsolated { self?.onEvent?(.remotePause) }
            return .success
        }
    }

    /// Lock screen details. iOS only shows them when Swellotic isn't mixing with another app.
    private func updateNowPlaying() {
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: settings.track == .musicApp ? "Breath" : settings.track.name,
            MPMediaItemPropertyArtist: "Swellotic",
            MPNowPlayingInfoPropertyIsLiveStream: true,
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? 1.0 : 0.0,
        ]
        if let artwork = Self.makeArtwork() { info[MPMediaItemPropertyArtwork] = artwork }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }

    /// iOS asks for the artwork from a background thread, so it's made outside the main actor.
    nonisolated private static func makeArtwork() -> MPMediaItemArtwork? {
        guard let image = UIImage(named: "NowPlayingArt") else { return nil }
        return MPMediaItemArtwork(boundsSize: image.size) { _ in image }
    }
}

/// A decoded file, handed from the background task that read it. It isn't changed after decoding.
private final class DecodedAudio: @unchecked Sendable {
    let buffer: AVAudioPCMBuffer
    init(buffer: AVAudioPCMBuffer) { self.buffer = buffer }
}
