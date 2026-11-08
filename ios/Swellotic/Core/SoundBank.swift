import Foundation
import Synchronization

/// The learned sounds, shared with the audio thread without locks.
///
/// The app decodes each file once, off the main thread, into memory that's never freed or changed, then publishes it.
/// Publishing sets a bit with release ordering, and the audio thread checks the bit with acquire ordering before reading,
/// so it only ever sees finished data. Nothing here allocates or retains on the audio thread.
final class SoundBank: @unchecked Sendable {
    /// Raw values index fixed storage, so don't reorder them.
    enum Slot: Int, CaseIterable, Sendable {
        case glass, metal, outside, wind, park, thunder1, thunder2, thunder3, thunder4, thunder5, thunder6

        /// The file's name in the app bundle.
        var fileName: String {
            switch self {
            case .glass: return "storm-glass"
            case .metal: return "storm-metal"
            case .outside: return "storm-outside"
            case .wind: return "wind"
            case .park: return "park"
            default: return "thunder\(rawValue - Slot.thunder1.rawValue + 1)"
            }
        }

        var fileExtension: String { rawValue >= Slot.thunder1.rawValue ? "mp3" : "wav" }

        static let thunder: [Slot] = [.thunder1, .thunder2, .thunder3, .thunder4, .thunder5, .thunder6]
    }

    /// One decoded sound: interleaved stereo, 16 bits a sample, at its own sample rate.
    struct Clip {
        let samples: UnsafePointer<Int16>
        let frames: Int
        let rate: Double
    }

    private let ready = Atomic<Int>(0)
    private let thrushReady = Atomic<Bool>(false)
    private let clips: UnsafeMutablePointer<Clip?>
    private var song: ThrushSong?

    init() {
        clips = .allocate(capacity: Slot.allCases.count)
        clips.initialize(repeating: nil, count: Slot.allCases.count)
    }

    /// Main or background thread. Takes ownership of `samples`, which must hold `frames * 2` values and never change.
    func publish(_ slot: Slot, samples: UnsafeMutablePointer<Int16>, frames: Int, rate: Double) {
        guard !isReady(slot), frames > 1, rate > 0 else { return }
        clips[slot.rawValue] = Clip(samples: UnsafePointer(samples), frames: frames, rate: rate)
        _ = ready.bitwiseOr(1 << slot.rawValue, ordering: .releasing)
    }

    /// Publishes the thrush's phrases. Call once.
    func publish(_ thrush: ThrushSong) {
        guard !thrushReady.load(ordering: .acquiring) else { return }
        song = thrush
        thrushReady.store(true, ordering: .releasing)
    }

    func isReady(_ slot: Slot) -> Bool { ready.load(ordering: .acquiring) & (1 << slot.rawValue) != 0 }

    /// Audio thread. Nil until the slot is published.
    @inline(__always) func clip(_ slot: Slot) -> Clip? {
        guard ready.load(ordering: .acquiring) & (1 << slot.rawValue) != 0 else { return nil }
        return clips[slot.rawValue]
    }

    /// Audio thread. Nil until published.
    @inline(__always) func thrush() -> ThrushSong? {
        guard thrushReady.load(ordering: .acquiring) else { return nil }
        return song
    }

    var hasThrush: Bool { thrushReady.load(ordering: .acquiring) }
}

/// A song thrush's phrases, traced from a recording: each note's pitch and loudness over time.
/// Stored flat in memory that's never freed, so the audio thread reads it without allocating.
final class ThrushSong: @unchecked Sendable {
    /// Seconds between pitch and loudness points.
    let step: Double
    let phraseCount: Int
    /// Per phrase: its first note and how many notes it has.
    let phraseFirst: UnsafeMutablePointer<Int>
    let phraseNotes: UnsafeMutablePointer<Int>
    /// Per note: when it starts within its phrase, where its points start, how many points, and its 2nd and 3rd harmonics.
    let noteStart: UnsafeMutablePointer<Double>
    let noteFirstPoint: UnsafeMutablePointer<Int>
    let notePoints: UnsafeMutablePointer<Int>
    let harmonic2: UnsafeMutablePointer<Double>
    let harmonic3: UnsafeMutablePointer<Double>
    /// Per point: pitch in hertz and loudness as a gain from 0 to 1.
    let pitch: UnsafeMutablePointer<Double>
    let loudness: UnsafeMutablePointer<Double>
    /// Pauses between phrases in the recording, in seconds.
    let gaps: UnsafeMutablePointer<Double>
    let gapCount: Int

    /// Reads the `thrush.json` made by tools/sound-lab/birds.py: `{"dt", "phrases": [[[start, [hz…], [dB…], [h2, h3]], …], …], "gaps": […]}`.
    init?(json data: Data) {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let dt = (root["dt"] as? NSNumber)?.doubleValue, dt > 0,
              let rawPhrases = root["phrases"] as? [[[Any]]] else { return nil }
        var starts: [Double] = [], firsts: [Int] = [], counts: [Int] = [], h2s: [Double] = [], h3s: [Double] = []
        var pitches: [Double] = [], levels: [Double] = [], pFirst: [Int] = [], pCount: [Int] = []
        // Loudness is measured against the loudest point in the phrases that are kept, as in app.js.
        var top = -Double.infinity
        for phrase in rawPhrases where phrase.count > 1 {
            for note in phrase {
                if let dbs = note.count > 2 ? note[2] as? [NSNumber] : nil { for d in dbs { top = max(top, d.doubleValue) } }
            }
        }
        guard top.isFinite else { return nil }
        for phrase in rawPhrases {
            let first = starts.count
            for note in phrase {
                guard note.count >= 4, let start = (note[0] as? NSNumber)?.doubleValue,
                      let hz = note[1] as? [NSNumber], let dbs = note[2] as? [NSNumber], let h = note[3] as? [NSNumber],
                      hz.count >= 2, hz.count == dbs.count, h.count >= 2 else { continue }
                starts.append(start)
                firsts.append(pitches.count)
                counts.append(hz.count)
                h2s.append(min(1, h[0].doubleValue)); h3s.append(min(1, h[1].doubleValue))
                for (f, d) in zip(hz, dbs) {
                    pitches.append(f.doubleValue)
                    levels.append(pow(10, (d.doubleValue - top) / 20))
                }
            }
            // Single notes sound like stray chirps, so only real phrases are kept, as in the web app.
            if starts.count - first > 1 { pFirst.append(first); pCount.append(starts.count - first) } else {
                starts.removeLast(starts.count - first); firsts.removeLast(firsts.count - first)
                let points = counts.suffix(counts.count - first).reduce(0, +)
                counts.removeLast(counts.count - first); h2s.removeLast(h2s.count - first); h3s.removeLast(h3s.count - first)
                pitches.removeLast(points); levels.removeLast(points)
            }
        }
        guard !pFirst.isEmpty else { return nil }
        let gapList = ((root["gaps"] as? [NSNumber]) ?? []).map(\.doubleValue)
        func copy<T>(_ a: [T]) -> UnsafeMutablePointer<T> {
            let p = UnsafeMutablePointer<T>.allocate(capacity: max(1, a.count))
            if !a.isEmpty { p.initialize(from: a, count: a.count) }
            return p
        }
        step = dt
        phraseCount = pFirst.count
        phraseFirst = copy(pFirst); phraseNotes = copy(pCount)
        noteStart = copy(starts); noteFirstPoint = copy(firsts); notePoints = copy(counts)
        harmonic2 = copy(h2s); harmonic3 = copy(h3s)
        pitch = copy(pitches); loudness = copy(levels)
        gaps = copy(gapList.isEmpty ? [1.0] : gapList); gapCount = max(1, gapList.count)
    }
}
