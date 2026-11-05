import SwiftUI

struct SettingsSheet: View {
    @ObservedObject var model: AppModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let s = model.settings
        let tint = s.palette.tint
        NavigationStack {
            ScrollView {
                VStack(spacing: 12) {
                    breathing(s, tint)
                    music(s, tint)
                    visuals(s, tint)
                }
                .padding(14)
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
    }

    private func open(_ key: String) -> Binding<Bool> {
        Binding(get: { model.settings.openSections.contains(key) },
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
                Picker("Breathing pattern", selection: $model.settings.pattern) {
                    ForEach(BreathPattern.allCases, id: \.self) { Text($0.name).tag($0) }
                }
                .pickerStyle(.segmented)
            }
            ToggleRow(title: "Slow down gradually", detail: "Starts at 10 breaths a minute and reaches your pace over 3 minutes.",
                      isOn: $model.settings.ease, tint: tint)
            Note(text: "Speed changes apply from the next breath. If you feel light-headed, stop and breathe normally.")
        }
    }

    private func music(_ s: Settings, _ tint: Color) -> some View {
        SettingsSection(title: "Music", summary: s.track.name, isOpen: open("music")) {
            ChipPicker(title: nil, choices: MusicTrack.allCases.map { Choice(value: $0, name: $0.name) },
                       selection: $model.settings.track, tint: tint)
            if s.track == .classical {
                ClassicalSaving(model: model, library: model.library, tint: tint)
            }
            Note(text: s.track.note)
            if s.track == .musicApp {
                ToggleRow(title: "Lower my music app", detail: "Turns your music app down while Swellotic plays, so the breath is easier to hear.",
                          isOn: $model.settings.lowerMusicApp, tint: tint)
            } else {
                ToggleRow(title: "Put music in the room", detail: "Keeps the breath close and makes the music sound further away in your headphones.",
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
