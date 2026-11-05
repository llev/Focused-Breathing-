import AudioToolbox
import AVFoundation
import MediaPlayer
import UIKit

/// Runs Swellotic's sound on Apple's audio engine.
///
/// Signal path:
/// breath → sum → limiter → output
/// generated music + Classical mix → music mixer → room filter → room reverb → sum
///
/// The app asks iOS for background audio (UIBackgroundModes in Info.plist), so sound keeps playing when the screen locks.
/// "My music app" mixes with other apps, so Spotify or Apple Music keep playing; everything else takes over the sound.
/// The playback category means the silent switch doesn't mute the breaths.
@MainActor
final class AudioController {
    enum Event {
        case paused, resumed, needsTap, headphonesGone, remoteToggle, remotePlay, remotePause
        /// The Classical mix moved to another piece.
        case pieceChanged(Int)
        /// A message about the Classical mix for the status line, or nil to clear it.
        case classical(String?)
    }

    var onEvent: ((Event) -> Void)?
    private(set) var synth = SynthEngine(sampleRate: 48_000)
    private(set) var isPlaying = false

    private var engine = AVAudioEngine()
    private var built = false
    private var format = AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 2)!
    /// Classical pieces are converted to this as they stream, and the music mixer converts them to the output rate.
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

    let library = ClassicalLibrary()
    private var stream: PieceStream?
    private var pieceRun = 0
    private(set) var currentPiece = 0
    private var failures = 0
    private var resting = false
    private var lastPosition = 0.0

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
        stream = nil

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
        c.interval.store(new.mode == .interval, ordering: .relaxed)
        c.swellSeconds.set(Double(new.swellMinutes * 60))
        c.restSeconds.set(Double(new.restMinutes * 60))
        // The chime stays audible even with the Breath slider low, as in the web app.
        c.chimeLevel.set(0.1 + 0.25 * volumeCurve(max(new.breathVolume, 30)))
        if built { applyRoom() }
        if rampTask == nil && stream != nil && !resting { player.volume = musicVolume }
        if old.saveAll != new.saveAll { library.setSaveAll(new.saveAll) }
        if !isPlaying { currentPiece = clampPiece(new.piece) }
        if isPlaying && old.lowerMusicApp != new.lowerMusicApp && new.track == .musicApp {
            configureSession()
            try? AVAudioSession.sharedInstance().setActive(true)
        }
        guard isPlaying, old.track != new.track else { return }
        configureSession()
        if new.track == .classical { playPiece(currentPiece) } else if old.track == .classical { stopClassical() }
        updateNowPlaying()
    }

    private var musicVolume: Float { Float(volumeCurve(settings.musicVolume)) }

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
        resting = false
        failures = 0
        if settings.track == .classical { playPiece(currentPiece) }
        updateNowPlaying()
    }

    func stop() {
        synth.controls.end()
        isPlaying = false
        resting = false
        stopClassical()
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
            // The phone stopped the engine, so carry on the piece from where it was.
            if settings.track == .classical { playPiece(currentPiece, from: lastPosition) }
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

    // MARK: Classical mix

    private func clampPiece(_ i: Int) -> Int {
        let n = library.pieces.count
        return n > 0 ? ((i % n) + n) % n : 0
    }

    /// Plays a piece from `seconds` in, downloading it first if it isn't on the phone yet.
    private func playPiece(_ requested: Int, from seconds: Double = 0) {
        guard isPlaying, settings.track == .classical, !library.pieces.isEmpty else { return }
        let index = clampPiece(requested)
        pieceRun += 1
        let run = pieceRun
        currentPiece = index
        lastPosition = seconds
        onEvent?(.pieceChanged(index))
        if !library.isSaved(index) { onEvent?(.classical("Loading the music…")) }
        Task { [weak self] in
            guard let self else { return }
            do {
                let url = try await self.library.fetch(index)
                guard run == self.pieceRun, self.isPlaying, self.settings.track == .classical else { return }
                try self.startStream(url: url, index: index, from: seconds, run: run)
                self.failures = 0
                self.onEvent?(.classical(nil))
                self.prefetch(after: index)
            } catch {
                guard run == self.pieceRun, self.isPlaying else { return }
                self.failures += 1
                let offline = error is URLError
                if self.failures >= self.library.pieces.count || (offline && self.library.savedCount == 0) {
                    self.onEvent?(.classical(offline
                        ? "Connect to the internet to play the classical mix, or turn on Save all for offline next time."
                        : "The classical music couldn't load. Try another sound."))
                    return
                }
                // Offline or a broken file: move on to the next piece that can play.
                self.playPiece(self.library.playable(from: index + 1, step: 1, online: !offline))
            }
        }
    }

    /// Downloads the next piece while this one plays, so the change is seamless.
    private func prefetch(after index: Int) {
        let next = clampPiece(index + 1)
        guard !library.isSaved(next) else { return }
        Task { [weak self] in _ = try? await self?.library.fetch(next) }
    }

    private func startStream(url: URL, index: Int, from seconds: Double, run: Int) throws {
        let s = try PieceStream(url: url, from: seconds, to: fileFormat)
        stream = s
        rampTask?.cancel()
        rampTask = nil
        player.stop()
        player.volume = 0
        // Keep about 12 seconds queued, read from the file a little at a time, so long pieces never sit in memory.
        for _ in 0..<3 { scheduleChunk(s, run: run) }
        player.play()
        if resting {
            player.pause()
        } else {
            rampPlayer(to: musicVolume, seconds: seconds > 0 ? 0.8 : 1.2)
        }
        updateNowPlaying()
    }

    private func scheduleChunk(_ s: PieceStream, run: Int) {
        guard run == pieceRun, !s.markedEnd else { return }
        let buffer: AVAudioPCMBuffer
        if let chunk = s.nextChunk(seconds: 4, format: fileFormat) {
            buffer = chunk
        } else {
            // The file ended on a chunk boundary: queue a moment of silence to learn when playback finishes.
            guard let silence = AVAudioPCMBuffer(pcmFormat: fileFormat, frameCapacity: 1) else { return }
            silence.frameLength = 1
            for c in 0..<Int(fileFormat.channelCount) { silence.floatChannelData?[c][0] = 0 }
            buffer = silence
        }
        let last = s.ended
        if last { s.markedEnd = true }
        player.scheduleBuffer(buffer, completionCallbackType: last ? .dataPlayedBack : .dataConsumed) { [weak self] _ in
            Task { @MainActor in
                guard let self, run == self.pieceRun else { return }
                if last { self.pieceEnded() } else { self.scheduleChunk(s, run: run) }
            }
        }
    }

    /// The set repeats by default, and "Repeat this piece" loops one.
    private func pieceEnded() {
        playPiece(settings.repeatOne ? currentPiece : currentPiece + 1)
    }

    /// Previous or next piece. Returns the new piece so the screen can show it.
    @discardableResult
    func skip(_ step: Int) -> Int {
        let next = clampPiece(currentPiece + step)
        failures = 0
        guard isPlaying, settings.track == .classical, stream != nil else {
            currentPiece = next
            return next
        }
        // A short fade, so skipping never cuts off mid-note.
        pieceRun += 1
        currentPiece = next
        rampPlayer(to: 0, seconds: 0.2) { [weak self] in self?.playPiece(next) }
        return next
    }

    private func stopClassical() {
        pieceRun += 1
        guard stream != nil else { return }
        stream = nil
        let run = pieceRun
        rampPlayer(to: 0, seconds: 0.3) { [weak self] in
            guard let self, self.pieceRun == run else { return }
            self.player.stop()
        }
    }

    /// How far into the current piece, and how long it is.
    func piecePosition() -> (now: Double, length: Double)? {
        guard let s = stream else { return nil }
        if let node = player.lastRenderTime, let t = player.playerTime(forNodeTime: node), t.sampleRate > 0 {
            lastPosition = min(s.duration, s.startOffset + Double(t.sampleTime) / t.sampleRate)
        }
        return (lastPosition, s.duration)
    }

    /// During a rest the piece fades out shortly after the chime and pauses. It carries on for the next swell.
    func setResting(_ isResting: Bool) {
        guard resting != isResting else { return }
        resting = isResting
        guard stream != nil else { return }
        if isResting {
            Task { [weak self] in
                try? await Task.sleep(for: .milliseconds(600))
                guard let self, self.resting else { return }
                self.rampPlayer(to: 0, seconds: 2.9) { [weak self] in
                    guard let self, self.resting else { return }
                    self.player.pause()
                }
            }
        } else {
            player.play()
            rampPlayer(to: musicVolume, seconds: 1.5)
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
            MPMediaItemPropertyTitle: nowPlayingTitle,
            MPMediaItemPropertyArtist: nowPlayingArtist,
            MPNowPlayingInfoPropertyIsLiveStream: true,
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? 1.0 : 0.0,
        ]
        if let artwork = Self.makeArtwork() { info[MPMediaItemPropertyArtwork] = artwork }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }

    private var nowPlayingTitle: String {
        if settings.track == .classical, library.pieces.indices.contains(currentPiece) { return library.pieces[currentPiece].heading }
        return settings.track == .musicApp ? "Breath" : settings.track.name
    }

    private var nowPlayingArtist: String {
        if settings.track == .classical, library.pieces.indices.contains(currentPiece) { return library.pieces[currentPiece].performer }
        return "Swellotic"
    }

    /// iOS asks for the artwork from a background thread, so it's made outside the main actor.
    nonisolated private static func makeArtwork() -> MPMediaItemArtwork? {
        guard let image = UIImage(named: "NowPlayingArt") else { return nil }
        return MPMediaItemArtwork(boundsSize: image.size) { _ in image }
    }
}

/// Reads one classical piece from the phone a few seconds at a time, converting it for the player.
private final class PieceStream {
    let file: AVAudioFile
    let converter: AVAudioConverter
    let duration: Double
    let startOffset: Double
    private(set) var ended = false
    var markedEnd = false

    init(url: URL, from seconds: Double, to format: AVAudioFormat) throws {
        file = try AVAudioFile(forReading: url)
        let rate = file.processingFormat.sampleRate
        duration = Double(file.length) / rate
        let start = AVAudioFramePosition(min(max(0, seconds), max(0, duration - 1)) * rate)
        file.framePosition = start
        startOffset = Double(start) / rate
        guard let c = AVAudioConverter(from: file.processingFormat, to: format) else { throw CocoaError(.fileReadCorruptFile) }
        if file.processingFormat.channelCount == 1 { c.channelMap = [0, 0] }
        converter = c
    }

    /// About `seconds` of sound, or nil once the piece has ended.
    func nextChunk(seconds: Double, format: AVAudioFormat) -> AVAudioPCMBuffer? {
        guard !ended, let out = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(seconds * format.sampleRate)) else { return nil }
        let source = file
        let inFormat = source.processingFormat
        var error: NSError?
        let status = converter.convert(to: out, error: &error) { packets, inStatus in
            guard let buffer = AVAudioPCMBuffer(pcmFormat: inFormat, frameCapacity: packets) else {
                inStatus.pointee = .endOfStream
                return nil
            }
            do { try source.read(into: buffer, frameCount: packets) } catch {
                inStatus.pointee = .endOfStream
                return nil
            }
            if buffer.frameLength == 0 {
                inStatus.pointee = .endOfStream
                return nil
            }
            inStatus.pointee = .haveData
            return buffer
        }
        if status == .endOfStream || status == .error { ended = true }
        return out.frameLength > 0 ? out : nil
    }
}
