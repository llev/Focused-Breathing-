import SwiftUI

extension SoundLayer {
    var name: String {
        switch self {
        case .glass: return "Rain on glass"
        case .metal: return "Taps on metal"
        case .outside: return "Rain outside"
        case .thunder: return "Thunder"
        case .wind: return "Wind"
        case .fire: return "Fire"
        case .crackles: return "Crackles"
        case .park: return "Park"
        case .birdsong: return "Birdsong"
        }
    }
}

/// What's been changed for the chosen sound, such as "Further away, more thunder", as in app.js.
func adjustSummary(_ s: Settings) -> String {
    let a = s.adjustment(s.track), d = SoundAdjust.designed(s.track)
    var parts: [String] = []
    if a.distance != d.distance { parts.append(a.distance > d.distance ? "further away" : "closer") }
    if a.tone != d.tone { parts.append(a.tone > d.tone ? "brighter" : "warmer") }
    for layer in s.track.layers where abs(a.layer(layer) - d.layer(layer)) > 8 {
        parts.append((a.layer(layer) > d.layer(layer) ? "more " : "less ") + layer.name.lowercased())
    }
    if a.low != 0 || a.middle != 0 || a.high != 0 { parts.append("fine tuned") }
    guard !parts.isEmpty else { return "As designed" }
    let text = parts.prefix(3).joined(separator: ", ") + (parts.count > 3 ? " and more" : "")
    return text.prefix(1).uppercased() + text.dropFirst()
}

/// The row under the sound chips that opens Adjust sound.
struct AdjustRow: View {
    let summary: String
    let tint: Color

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "slider.horizontal.3")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 36, height: 36)
                .background(tint.opacity(0.18), in: Circle())
            VStack(alignment: .leading, spacing: 1) {
                Text("Adjust sound").font(.body.weight(.semibold))
                Text(summary).font(.subheadline).foregroundStyle(Color.soft)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right").font(.system(size: 14, weight: .semibold)).foregroundStyle(Color.soft)
        }
        .padding(.horizontal, 12)
        .frame(minHeight: 56)
        .background(Color.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Color.white.opacity(0.14), lineWidth: 1))
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityHint("Opens Distance, Tone and Fine tune for this sound")
    }
}

/// Distance and Tone, with Fine tune folded away until it's wanted: the sound's Mix layers, if it has any, and Low,
/// Middle and High. Changes are kept for each sound.
struct AdjustSoundView: View {
    @ObservedObject var model: AppModel
    @State private var showFine = false

    private var track: MusicTrack { model.settings.track }
    private var current: SoundAdjust { model.settings.adjustment(track) }

    private func store(_ a: SoundAdjust) {
        let key = String(track.rawValue)
        model.settings.adjust[key] = a == SoundAdjust.designed(track) ? nil : a
    }

    private func value(_ path: WritableKeyPath<SoundAdjust, Double>) -> Binding<Double> {
        Binding(get: { current[keyPath: path] },
                set: { v in var a = current; a[keyPath: path] = v.rounded(); store(a) })
    }

    private func layer(_ l: SoundLayer) -> Binding<Double> {
        Binding(get: { current.layer(l) },
                set: { v in var a = current; a.layers[l.rawValue] = v.rounded(); store(a) })
    }

    private var fineSummary: String {
        let d = SoundAdjust.designed(track)
        let mix = track.layers.contains { current.layer($0) != d.layer($0) }
        let bands = current.low != 0 || current.middle != 0 || current.high != 0
        return mix && bands ? "Mix and frequencies changed" : mix ? "Mix changed" : bands ? "Frequencies changed" : "Not changed"
    }

    var body: some View {
        let tint = model.tint
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                EndsSlider(title: "Distance", low: "Near", high: "Far", value: value(\.distance), range: 0...100, tint: tint)
                EndsSlider(title: "Tone", low: "Warm", high: "Bright", value: value(\.tone), range: -100...100, tint: tint)

                Button {
                    withAnimation(.snappy(duration: 0.25)) { showFine.toggle() }
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 1) {
                            Text("Fine tune").font(.body.weight(.semibold))
                            Text(fineSummary).font(.subheadline).foregroundStyle(Color.soft)
                        }
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.down")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Color.soft)
                            .rotationEffect(.degrees(showFine ? 180 : 0))
                    }
                    .frame(minHeight: 52)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .overlay(alignment: .top) { Rectangle().fill(Color.white.opacity(0.14)).frame(height: 1).offset(y: -10) }
                .accessibilityValue(showFine ? "Open" : fineSummary)

                if showFine {
                    VStack(alignment: .leading, spacing: 16) {
                        if !track.layers.isEmpty {
                            Text("Mix").font(.subheadline.weight(.semibold))
                            ForEach(track.layers, id: \.self) { l in
                                LevelSlider(title: l.name, value: layer(l), range: 0...100, readout: nil, tint: tint)
                            }
                        }
                        Text("Frequencies").font(.subheadline.weight(.semibold)).padding(.top, track.layers.isEmpty ? 0 : 6)
                        LevelSlider(title: "Low", value: value(\.low), range: -12...12, readout: signed(current.low), tint: tint)
                        LevelSlider(title: "Middle", value: value(\.middle), range: -12...12, readout: signed(current.middle), tint: tint)
                        LevelSlider(title: "High", value: value(\.high), range: -12...12, readout: signed(current.high), tint: tint)
                    }
                    .transition(.opacity)
                }

                Button("Reset to how it was designed") { model.settings.adjust[String(track.rawValue)] = nil }
                    .font(.body.weight(.semibold))
                    .foregroundStyle(tint)
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .padding(20)
        }
        .navigationTitle(track.name)
        .navigationBarTitleDisplayMode(.inline)
    }

    private func signed(_ v: Double) -> String { v > 0 ? "+\(Int(v))" : v < 0 ? "−\(Int(-v))" : "0" }
}

/// A slider with words at each end, such as Near and Far.
private struct EndsSlider: View {
    let title: String
    let low: String
    let high: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.subheadline.weight(.semibold))
            Slider(value: $value, in: range, step: 1).tint(tint)
                .accessibilityLabel(title)
                .accessibilityValue(value == (range.lowerBound + range.upperBound) / 2 && range.lowerBound < 0 ? "Middle"
                                    : "\(Int(((value - range.lowerBound) / (range.upperBound - range.lowerBound) * 100).rounded())) percent towards \(high)")
            HStack {
                Text(low)
                Spacer()
                Text(high)
            }
            .font(.footnote)
            .foregroundStyle(Color.soft)
            .accessibilityHidden(true)
        }
    }
}

/// A slider with its name on the left and, if given, its setting on the right.
private struct LevelSlider: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let readout: String?
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(title).font(.subheadline.weight(.semibold))
                Spacer()
                if let readout { Text(readout).font(.subheadline.monospacedDigit()).foregroundStyle(Color.soft) }
            }
            Slider(value: $value, in: range, step: 1).tint(tint)
                .accessibilityLabel(title)
                .accessibilityValue(readout.map { "\($0) decibels" } ?? "\(Int(value)) percent")
        }
    }
}
