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
    case brown, pink, rain, beach, stream, wind, fire, ambient, keys, classical, musicApp

    /// Generated tracks are made in code. The Classical mix and "My music app" are not.
    var isGenerated: Bool { self != .classical && self != .musicApp }
}

/// Slider positions feel more even to the ear when squared, as in the web app.
@inline(__always) func volumeCurve(_ percent: Double) -> Double {
    let v = min(100, max(0, percent)) / 100
    return v * v
}

@inline(__always) func midiToHz(_ note: Double) -> Double {
    440 * pow(2, (note - 69) / 12)
}
