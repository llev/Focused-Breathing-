import SwiftUI

/// The session drawer, opened from the session button. The open tab is the kind of session: Timer or Interval.
/// Changes apply straight away, even mid-session, as in the web app.
struct SessionSheet: View {
    @ObservedObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    /// Closes the panel. Side panels and popovers are closed by their owner, so it's passed in.
    var close: (() -> Void)? = nil
    @State private var contentHeight: CGFloat = 320

    var body: some View {
        let s = model.settings
        let tint = s.palette.tint
        VStack(spacing: 0) {
            // Its own header rather than a navigation bar, which a popover on iPad cut off at the top.
            ZStack {
                Text("Session").font(.headline)
                    .accessibilityAddTraits(.isHeader)
                HStack {
                    Spacer()
                    Button("Done") { if let close { close() } else { dismiss() } }
                        .font(.body.weight(.semibold))
                        .foregroundStyle(tint)
                        .frame(minWidth: 44, minHeight: 44)
                }
            }
            .padding(.horizontal, 18)
            .padding(.top, 12)
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    SegmentedChoice(title: "Session type", choices: SessionMode.allCases.map { Choice(value: $0, name: $0.name) },
                                    selection: $model.settings.mode)

                    if s.mode == .timer {
                        Note(text: "Breathe until you end the session, or for a set time.")
                        ChipPicker(title: "Stop after",
                                   choices: Settings.limits.map { Choice(value: $0, name: Self.limitName($0)) },
                                   selection: $model.settings.limit, tint: tint)
                        if s.limit == Settings.custom {
                            minutes("Custom length", value: $model.settings.customMinutes, range: 5...240, step: 5)
                        }
                    } else {
                        Note(text: "Take turns between a swell, for focus, and a rest, for a quiet break. Sound pauses while you rest, and a soft chime marks each change.")
                        minutes("Swell", value: $model.settings.swellMinutes, range: 5...90, step: 5)
                        minutes("Rest", value: $model.settings.restMinutes, range: 1...30, step: 1)
                        ChipPicker(title: "Rounds",
                                   choices: Settings.roundChoices.map { Choice(value: $0, name: $0 == 0 ? "Until I stop" : "\($0) rounds") },
                                   selection: $model.settings.rounds, tint: tint)
                        Note(text: s.rounds > 0
                             ? "\(s.rounds) swells with a rest between each, \(Int(s.sessionLength / 60)) minutes in all."
                             : "Swell and rest take turns until you end the session.")
                    }
                }
                .padding(18)
                .frame(maxWidth: .infinity, alignment: .leading)
                .frosted(cornerRadius: 22)
                .padding(14)
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { contentHeight = $0 }
            }
            // A popover on iPad takes its ideal height, so it fits the content instead of leaving space below.
            .frame(idealHeight: contentHeight)
            .scrollBounceBehavior(.basedOnSize)
        }
    }

    private static func limitName(_ minutes: Int) -> String {
        switch minutes {
        case 0: return "No limit"
        case Settings.custom: return "Custom"
        default: return "\(minutes) min"
        }
    }

    /// A slider for whole minutes, with its value shown beside the label.
    private func minutes(_ title: String, value: Binding<Int>, range: ClosedRange<Int>, step: Int) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(title).font(.subheadline.weight(.semibold))
                Spacer()
                Text("\(value.wrappedValue) min").font(.subheadline.monospacedDigit()).foregroundStyle(Color.soft)
            }
            Slider(value: Binding(get: { Double(value.wrappedValue) }, set: { value.wrappedValue = Int($0.rounded()) }),
                   in: Double(range.lowerBound)...Double(range.upperBound), step: Double(step))
                .accessibilityLabel(title)
                .accessibilityValue("\(value.wrappedValue) minutes")
        }
    }
}
