import SwiftUI

struct SettingsSheet: View {
    @ObservedObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    /// Closes the panel. Side panels and popovers are closed by their owner, so it's passed in.
    var close: (() -> Void)? = nil
    /// True in the iPad and Mac side panel. Every section starts open there, and closing one is remembered apart
    /// from the iPhone sheet's open sections.
    var sidePanel = false

    var body: some View {
        let s = model.settings
        let tint = s.palette.tint
        NavigationStack {
            ScrollView {
                VStack(spacing: 12) {
                    breathing(s, tint)
                    sounds(s, tint)
                    visuals(s, tint)
                    HStack(spacing: 8) {
                        Link("Help", destination: URL(string: "https://swellotic.com/support.html")!).padding(.horizontal, 12)
                        Link("Privacy", destination: URL(string: "https://swellotic.com/privacy.html")!).padding(.horizontal, 12)
                    }
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Color.soft)
                    .buttonStyle(.plain)
                    .frame(minHeight: 44)
                }
                .padding(14)
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { if let close { close() } else { dismiss() } } }
            }
        }
    }

    private func open(_ key: String) -> Binding<Bool> {
        if sidePanel {
            return Binding(get: { !model.settings.closedInPanel.contains(key) },
                           set: { isOpen in
                               if isOpen { model.settings.closedInPanel.remove(key) } else { model.settings.closedInPanel.insert(key) }
                           })
        }
        return Binding(get: { model.settings.openSections.contains(key) },
                       set: { isOpen in
                           if isOpen { model.settings.openSections.insert(key) } else { model.settings.openSections.remove(key) }
                       })
    }

    private func breathing(_ s: Settings, _ tint: Color) -> some View {
        let cycle = 60 / s.bpm, inhale = cycle * s.pattern.inhaleShare
        return SettingsSection(title: "Breathing", summary: "\(formatPace(s.bpm)) a minute, \(s.sound.name)", isOpen: open("breathing")) {
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text("Breaths per minute").font(.subheadline.weight(.semibold))
                    Spacer()
                    Text("\(formatPace(s.bpm)) (\(String(format: "%.1f", inhale)) s in, \(String(format: "%.1f", cycle - inhale)) s out)")
                        .font(.subheadline.monospacedDigit()).foregroundStyle(Color.soft)
                }
                Slider(value: $model.settings.bpm, in: 2...12, step: 0.5)
                    .accessibilityLabel("Breaths per minute")
                    .accessibilityValue(formatPace(s.bpm))
            }
            ChipPicker(title: "Breath sound", choices: BreathSound.allCases.map { Choice(value: $0, name: $0.name) },
                       selection: $model.settings.sound, tint: tint)
            VStack(alignment: .leading, spacing: 8) {
                Text("Breathing pattern").font(.subheadline.weight(.semibold))
                SegmentedChoice(title: "Breathing pattern", choices: BreathPattern.allCases.map { Choice(value: $0, name: $0.name) },
                                selection: $model.settings.pattern)
            }
            ToggleRow(title: "Slow down gradually", detail: "Starts at 10 breaths a minute and reaches your pace over 3 minutes.",
                      isOn: $model.settings.ease, tint: tint)
            Note(text: "Speed changes apply from the next breath. If you feel light-headed, stop and breathe normally.")
        }
    }

    /// The Sounds section: moods, then noise, then gentle music, with Adjust sound for the chosen one.
    /// Its key stays "music" so the open sections people saved carry over.
    private func sounds(_ s: Settings, _ tint: Color) -> some View {
        SettingsSection(title: "Sounds", summary: s.track.name + (s.track.adjustable && s.adjusted(s.track) ? ", adjusted" : ""), isOpen: open("music")) {
            ChipPicker(title: "Moods", choices: MusicTrack.moods.map { Choice(value: $0, name: $0.name) },
                       selection: $model.settings.track, tint: tint)
            ChipPicker(title: "Noise", choices: MusicTrack.noise.map { Choice(value: $0, name: $0.name) },
                       selection: $model.settings.track, tint: tint)
            ChipPicker(title: "Gentle music", choices: MusicTrack.gentleMusic.map { Choice(value: $0, name: $0.name) },
                       selection: $model.settings.track, tint: tint)
            if s.track.adjustable {
                NavigationLink {
                    AdjustSoundView(model: model)
                } label: {
                    AdjustRow(summary: adjustSummary(s), tint: tint)
                }
                .buttonStyle(.plain)
            }
            if s.track == .classical {
                ClassicalSaving(model: model, library: model.library, tint: tint)
            }
            Note(text: s.track.note)
            if s.track == .musicApp {
                ToggleRow(title: "Lower my music app", detail: "Turns your music app down while Swellotic plays, so the breath is easier to hear.",
                          isOn: $model.settings.lowerMusicApp, tint: tint)
            } else {
                ToggleRow(title: "Put sounds in the room", detail: "Keeps the breath close and makes the sounds seem further away in your headphones.",
                          isOn: $model.settings.room, tint: tint)
            }
        }
    }

    private func visuals(_ s: Settings, _ tint: Color) -> some View {
        SettingsSection(title: "Visuals", summary: "\(s.scene.name), \(s.palette.name)", isOpen: open("visuals")) {
            ChipPicker(title: "Scene", choices: SceneStyle.allCases.map { Choice(value: $0, name: $0.name) },
                       selection: $model.settings.scene, tint: tint)
            ChipPicker(title: "Colours", choices: Palette.allCases.map { Choice(value: $0, name: $0.name) },
                       selection: $model.settings.palette, tint: tint)
            ToggleRow(title: "In and Out", isOn: $model.settings.showWords, tint: tint)
            ToggleRow(title: "Countdown", isOn: $model.settings.countdown, tint: tint)
        }
    }
}

/// The Classical mix's place in the set, and "Save all for offline".
struct ClassicalSaving: View {
    @ObservedObject var model: AppModel
    @ObservedObject var library: ClassicalLibrary
    let tint: Color

    var body: some View {
        let total = library.pieces.count
        VStack(alignment: .leading, spacing: 10) {
            if total > 0 { Note(text: "Playing piece \(model.settings.piece + 1) of \(total).") }
            ToggleRow(title: "Save all for offline",
                      detail: "\(library.savedCount) of \(total) pieces saved on this phone." + (library.savingAll ? " Saving \(min(total, library.savedCount + 1))…" : ""),
                      isOn: $model.settings.saveAll, tint: tint)
        }
    }
}
