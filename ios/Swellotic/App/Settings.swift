import SwiftUI

enum SceneStyle: Int, CaseIterable, Codable {
    case lava, bloom, rings, aurora, tide
}

enum Palette: Int, CaseIterable, Codable {
    case sunset, sea, ember, meadow, heather, night

    var tint: Color { Color(hex: tintHex) }
    var onTint: Color { Color(hex: 0x17121F) }

    private var tintHex: UInt32 {
        switch self {
        case .sunset: return 0xFFB27A
        case .sea: return 0x7FE3D3
        case .ember: return 0xFF9A5C
        case .meadow: return 0xB7E36A
        case .heather: return 0xD2A6FF
        case .night: return 0xA9B8FF
        }
    }

    var ground: [Color] {
        switch self {
        case .sunset: return [Color(hex: 0x2A1238), Color(hex: 0x5A1F3F)]
        case .sea: return [Color(hex: 0x0D2B3A), Color(hex: 0x123F4F)]
        case .ember: return [Color(hex: 0x2B0A12), Color(hex: 0x4A0F1C)]
        case .meadow: return [Color(hex: 0x0F2A1E), Color(hex: 0x1C3F2A)]
        case .heather: return [Color(hex: 0x1F1638), Color(hex: 0x3B1F55)]
        case .night: return [Color(hex: 0x07080F), Color(hex: 0x0E1020)]
        }
    }

    var colors: [Color] {
        switch self {
        case .sunset: return [Color(hex: 0xFF7A59), Color(hex: 0xFFB347), Color(hex: 0xE8487E)]
        case .sea: return [Color(hex: 0x3FB6B2), Color(hex: 0x2F8FD0), Color(hex: 0x8FE0C8)]
        case .ember: return [Color(hex: 0xFF4D2E), Color(hex: 0xFF9A1F), Color(hex: 0xD61F6B)]
        case .meadow: return [Color(hex: 0x6FCF6A), Color(hex: 0xD6D44C), Color(hex: 0x2FAE8A)]
        case .heather: return [Color(hex: 0xB377E8), Color(hex: 0xF08FC8), Color(hex: 0x6D8CF0)]
        case .night: return [Color(hex: 0x2B3A6B), Color(hex: 0x3C2F63), Color(hex: 0x1F4A5C)]
        }
    }
}

/// Adjust sound: how far away a sound is, its tone, three frequency bands and its Mix layers.
/// Distance runs 0 to 100, Tone −100 (warm) to 100 (bright), the bands −12 to 12 dB, and layers 0 to 100 with 50 as designed.
struct SoundAdjust: Codable, Equatable {
    var distance = 0.0
    var tone = 0.0
    var low = 0.0, middle = 0.0, high = 0.0
    var layers: [String: Double] = [:]

    func layer(_ l: SoundLayer) -> Double { layers[l.rawValue] ?? 50 }

    /// How each sound starts, matching app.js.
    static func designed(_ track: MusicTrack) -> SoundAdjust {
        var a = SoundAdjust()
        switch track {
        case .window: a.tone = -75
        case .storm: a.distance = 20; a.tone = -15; a.layers = [SoundLayer.wind.rawValue: 30]
        case .park: a.distance = 15; a.layers = [SoundLayer.park.rawValue: 38, SoundLayer.birdsong.rawValue: 62]
        case .hill: a.distance = 25
        case .beach: a.distance = 30; a.tone = -10
        case .fire: a.distance = 10; a.tone = -20
        default: break
        }
        return a
    }
}

/// Everything the person has chosen. Saved on the device only.
enum SessionMode: Int, CaseIterable, Codable {
    case timer, interval

    var name: String { self == .timer ? "Timer" : "Interval" }
}

struct Settings: Codable, Equatable {
    var bpm = 6.0
    var pattern = BreathPattern.even
    var sound = BreathSound.bowl
    var breathVolume = 35.0
    var musicVolume = 55.0
    var room = true
    var lowerMusicApp = true
    var ease = false
    var track = MusicTrack.brown
    /// Timer: minutes to stop after, 0 for no limit, or `Settings.custom` to use `customMinutes`.
    var limit = 0
    var customMinutes = 40
    var mode = SessionMode.timer
    var swellMinutes = 25
    var restMinutes = 5
    /// Interval rounds: 0 means until stopped.
    var rounds = 4
    /// Classical mix: which piece is playing, whether to repeat it, and whether to keep the whole set on the phone.
    var piece = 0
    var repeatOne = false
    var saveAll = false
    var scene = SceneStyle.lava
    var palette = Palette.sunset
    var showWords = true
    var countdown = false
    var openSections: Set<String> = ["breathing"]
    /// Adjust sound settings, by the track's number, for sounds that have been changed.
    var adjust: [String: SoundAdjust] = [:]

    func adjustment(_ track: MusicTrack) -> SoundAdjust { adjust[String(track.rawValue)] ?? SoundAdjust.designed(track) }
    func adjusted(_ track: MusicTrack) -> Bool { adjustment(track) != SoundAdjust.designed(track) }

    static let custom = -1
    static let limits = [0, 25, 50, 90, custom]
    static let roundChoices = [0, 2, 4, 6]

    /// How many minutes a timer stops after, or 0 for no limit.
    var limitMinutes: Int { limit == Self.custom ? customMinutes : limit }

    var plan: IntervalPlan { IntervalPlan(swell: Double(swellMinutes * 60), rest: Double(restMinutes * 60)) }

    /// How long the whole session lasts in seconds, or 0 for no end. Interval sessions end after the last swell.
    var sessionLength: Double {
        mode == .interval ? plan.length(rounds: rounds) : Double(limitMinutes * 60)
    }
    private static let key = "swellotic-settings"

    init() {}

    /// Unknown or missing values fall back to the defaults, so an update never loses everything else.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = Settings()
        func v<T: Decodable>(_ key: CodingKeys, _ fallback: T) -> T { (try? c.decodeIfPresent(T.self, forKey: key)) ?? fallback }
        bpm = min(12, max(2, v(.bpm, d.bpm)))
        pattern = v(.pattern, d.pattern)
        sound = v(.sound, d.sound)
        breathVolume = v(.breathVolume, d.breathVolume)
        musicVolume = v(.musicVolume, d.musicVolume)
        room = v(.room, d.room)
        lowerMusicApp = v(.lowerMusicApp, d.lowerMusicApp)
        ease = v(.ease, d.ease)
        track = v(.track, d.track)
        // Rain and Wind became moods.
        if track == .rain { track = .window }
        if track == .wind { track = .hill }
        limit = v(.limit, d.limit)
        customMinutes = min(240, max(5, v(.customMinutes, d.customMinutes)))
        mode = v(.mode, d.mode)
        swellMinutes = min(90, max(5, v(.swellMinutes, d.swellMinutes)))
        restMinutes = min(30, max(1, v(.restMinutes, d.restMinutes)))
        rounds = v(.rounds, d.rounds)
        piece = max(0, v(.piece, d.piece))
        repeatOne = v(.repeatOne, d.repeatOne)
        saveAll = v(.saveAll, d.saveAll)
        scene = v(.scene, d.scene)
        palette = v(.palette, d.palette)
        showWords = v(.showWords, d.showWords)
        countdown = v(.countdown, d.countdown)
        openSections = v(.openSections, d.openSections)
        adjust = v(.adjust, d.adjust)
    }

    static func load() -> Settings {
        guard let data = UserDefaults.standard.data(forKey: key),
              let s = try? JSONDecoder().decode(Settings.self, from: data) else { return Settings() }
        return s
    }

    func save() {
        if let data = try? JSONEncoder().encode(self) { UserDefaults.standard.set(data, forKey: Self.key) }
    }
}

// Names people see. UK English, named by what people recognise (see CLAUDE.md).

extension BreathSound {
    var name: String {
        switch self {
        case .bowl: return "Singing bowl"
        case .gong: return "Gong"
        case .piano: return "Soft piano"
        case .wood: return "Wooden marimba"
        case .tone: return "Soft hum"
        case .chime: return "Chime"
        case .ocean: return "Ocean"
        case .silent: return "Silent"
        }
    }
}

extension BreathPattern {
    var name: String {
        switch self {
        case .even: return "Even"
        case .long: return "Longer out"
        case .longest: return "Much longer out"
        }
    }
}

extension MusicTrack {
    var name: String {
        switch self {
        case .brown: return "Brown noise"
        case .pink: return "Pink noise"
        case .green: return "Green noise"
        case .rain: return "Rain"
        case .wind: return "Wind"
        case .window: return "Rain on the window"
        case .storm: return "Night storm"
        case .fire: return "Fireside"
        case .stream: return "Woodland stream"
        case .beach: return "Calm shore"
        case .park: return "Winter park"
        case .hill: return "Wind on the hill"
        case .ambient: return "Ambient"
        case .keys: return "Soft keys"
        case .classical: return "Classical mix"
        case .musicApp: return "My music app"
        }
    }

    /// The Sounds section's three groups. Rain and Wind aren't offered any more: the moods replaced them.
    static let moods: [MusicTrack] = [.window, .storm, .fire, .stream, .beach, .park, .hill]
    static let noise: [MusicTrack] = [.brown, .pink, .green]
    static let gentleMusic: [MusicTrack] = [.ambient, .keys, .classical, .musicApp]

    /// Every sound except "My music app" can be adjusted.
    var adjustable: Bool { self != .musicApp }

    var note: String {
        switch self {
        // What you'll hear, then whether it works offline. Keep these in step with app.js.
        case .window: return "Rain against glass, a few taps on metal, and heavier rain outside. Shaped from a real recording, and built into the app, so it works offline."
        case .storm: return "Heavy rain with thunder rolling through, and a little wind. Shaped from a real recording, and built into the app, so it works offline."
        case .park: return "A quiet park on a cold day, with a song thrush singing nearby. Shaped from a real recording, and built into the app, so it works offline."
        case .hill: return "Slow, uneven gusts of wind across open ground. Built into the app, so it works offline."
        case .fire: return "A low, steady fire with gentle crackles. Made on your phone, so it works offline."
        case .stream: return "Water running over stones, steady and soft. Made on your phone, so it works offline."
        case .beach: return "Slow, soft waves rolling in and drawing back. Made on your phone, so it works offline."
        case .brown: return "A deep, soft rumble, with most of its weight in the low sounds. Made on your phone, so it works offline."
        case .pink: return "A steady, even hiss, softer than white noise. Made on your phone, so it works offline."
        case .green: return "A gentle hiss centred on the middle sounds. Made on your phone, so it works offline."
        case .ambient: return "Slow, warm chords that drift gently from one to the next. Made on your phone, so it works offline."
        case .keys: return "Quiet, unhurried piano notes over a low note every few seconds. Made on your phone, so it works offline."
        case .classical: return "Calm public domain recordings made for Musopen, shared on Wikimedia Commons. The set repeats when it reaches the end, and pieces you listen to are saved for offline use."
        case .musicApp: return "Play music in Spotify, Apple Music or any other app, then press play here. The Breath slider changes only the breaths, and your music app controls the music. The side buttons change both, so use the Breath slider to balance them."
        default: return "Made on your phone, so it works offline."
        }
    }
}

extension SceneStyle {
    var name: String {
        switch self {
        case .lava: return "Lava lamp"
        case .bloom: return "Bloom"
        case .rings: return "Rings"
        case .aurora: return "Aurora"
        case .tide: return "Tide"
        }
    }
}

extension Palette {
    var name: String {
        switch self {
        case .sunset: return "Sunset"
        case .sea: return "Sea"
        case .ember: return "Ember"
        case .meadow: return "Meadow"
        case .heather: return "Heather"
        case .night: return "Night"
        }
    }
}

extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        self.init(.sRGB, red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255, opacity: opacity)
    }

    static let night = Color(hex: 0x15111D)
    static let soft = Color.white.opacity(0.72)
    static let well = Color.white.opacity(0.11)
}

/// "6" rather than "6.0", but "6.5" stays as it is.
func formatPace(_ bpm: Double) -> String {
    bpm.rounded() == bpm ? String(Int(bpm)) : String(format: "%.1f", bpm)
}
