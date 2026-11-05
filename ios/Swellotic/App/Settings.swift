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

/// Everything the person has chosen. Saved on the device only.
struct Settings: Codable, Equatable {
    var bpm = 6.0
    var pattern = BreathPattern.even
    var sound = BreathSound.bowl
    var breathVolume = 35.0
    var musicVolume = 55.0
    var room = true
    var ease = false
    var haptics = false
    var track = MusicTrack.brown
    var limit = 0
    var scene = SceneStyle.lava
    var palette = Palette.sunset
    var showWords = true
    var countdown = false
    var openSections: Set<String> = ["breathing"]

    static let limits = [0, 25, 50, 90]
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
        ease = v(.ease, d.ease)
        haptics = v(.haptics, d.haptics)
        track = v(.track, d.track)
        limit = v(.limit, d.limit)
        scene = v(.scene, d.scene)
        palette = v(.palette, d.palette)
        showWords = v(.showWords, d.showWords)
        countdown = v(.countdown, d.countdown)
        openSections = v(.openSections, d.openSections)
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
        case .rain: return "Rain"
        case .beach: return "Beach"
        case .stream: return "Stream"
        case .wind: return "Wind"
        case .fire: return "Fireplace"
        case .ambient: return "Ambient"
        case .keys: return "Soft keys"
        case .files: return "Audio files"
        case .musicApp: return "My music app"
        }
    }

    var note: String {
        switch self {
        case .beach: return "Slow, soft waves generated on your phone, so it works offline."
        case .ambient: return "Slow chords generated on your phone, so it works offline."
        case .keys: return "A simple generated sketch, not a finished recording."
        case .files: return "Add audio files from this phone. They stay on your phone, play on a loop and are cleared when Swellotic closes."
        case .musicApp: return "Play music in Spotify, Apple Music or any other app, then press play here. The Breath slider changes only the breaths, and your music app controls the music. The side buttons change both, so use the Breath slider to balance them."
        default: return "Generated on your phone, so it works offline."
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
