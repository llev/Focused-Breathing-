// The core folder is plain Swift with no Apple-only frameworks, so it can be tested with `swift test` (see ios/Package.swift).
// It must never import UIKit, SwiftUI or AVFoundation.

import Foundation

/// The sound that marks each breath. Raw values are shared with the audio thread, so don't reorder them.
enum BreathSound: Int, CaseIterable, Codable, Sendable {
    case bowl, gong, piano, wood, tone, chime, ocean, silent
}

/// How a breath is split between in and out.
enum BreathPattern: Int, CaseIterable, Codable, Sendable {
    case even, long, longest

    var inhaleShare: Double {
        switch self {
        case .even: return 0.5
        case .long: return 0.4
        case .longest: return 1.0 / 3.0
        }
    }
}

/// The background sound. Raw values are shared with the audio thread, so don't reorder them.
enum MusicTrack: Int, CaseIterable, Codable, Sendable {
    // Classical replaced "Audio files" and keeps its number, so saved settings carry over.
    // Rain and Wind became the Rain on the window and Wind on the hill moods; they stay here so old settings still load.
    case brown, pink, rain, beach, stream, wind, fire, ambient, keys, classical, musicApp
    case green, window, storm, park, hill

    /// Generated tracks are made in code. The Classical mix and "My music app" are not.
    var isGenerated: Bool { self != .classical && self != .musicApp }

    /// Moods that play files learned from recordings, so they're silent until those files are loaded.
    var isLearned: Bool { self == .window || self == .storm || self == .park || self == .hill }

    /// The files a mood needs, in the order they're best loaded.
    var soundSlots: [SoundBank.Slot] {
        switch self {
        case .window: return [.outside, .glass, .metal]
        case .storm: return [.outside, .glass, .metal, .wind] + SoundBank.Slot.thunder
        case .park: return [.park]
        case .hill: return [.wind]
        default: return []
        }
    }

    /// The Mix sliders' layers, by their place in SynthControls.
    var layers: [SoundLayer] {
        switch self {
        case .window: return [.glass, .metal, .outside]
        case .storm: return [.glass, .metal, .outside, .thunder, .wind]
        case .fire: return [.fire, .crackles]
        case .park: return [.park, .birdsong]
        default: return []
        }
    }
}

/// A part of a sound with its own Mix slider. `index` is its place in SynthControls.
enum SoundLayer: String, CaseIterable, Codable, Sendable {
    case glass, metal, outside, thunder, wind, fire, crackles, park, birdsong

    var index: Int {
        switch self {
        case .glass, .fire, .park: return 0
        case .metal, .crackles, .birdsong: return 1
        case .outside: return 2
        case .thunder: return 3
        case .wind: return 4
        }
    }
}

/// Slider positions feel more even to the ear when squared, as in the web app.
@inline(__always) func volumeCurve(_ percent: Double) -> Double {
    let v = min(100, max(0, percent)) / 100
    return v * v
}

@inline(__always) func midiToHz(_ note: Double) -> Double {
    440 * pow(2, (note - 69) / 12)
}
