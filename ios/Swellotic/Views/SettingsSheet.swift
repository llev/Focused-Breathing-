import SwiftUI
import UniformTypeIdentifiers

struct SettingsSheet: View {
    @ObservedObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var choosingFiles = false

    var body: some View {
        let s = model.settings
        let tint = s.palette.tint
        NavigationStack {
            ScrollView {
                VStack(spacing: 12) {
                    breathing(s, tint)
                    music(s, tint)
                    visuals(s, tint)
                    session(s, tint)
                }
                .padding(14)
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
        .fileImporter(isPresented: $choosingFiles, allowedContentTypes: [.audio], allowsMultipleSelection: true) { result in
            if case let .success(urls) = result { model.addFiles(urls) }
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
            if s.track == .files {
                VStack(alignment: .leading, spacing: 8) {
                    Button("Add audio files") { choosingFiles = true }
                        .font(.body.weight(.medium))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 16)
                        .frame(minHeight: 44)
                        .background(Color.well, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    ForEach(Array(model.fileNames.enumerated()), id: \.offset) { i, name in
                        Text("\(i + 1). \(name)").font(.subheadline).foregroundStyle(Color.soft)
                    }
                }
            }
            Note(text: s.track.note)
            ToggleRow(title: "Put music in the room", detail: "Keeps the breath close and makes the music sound further away in your headphones.",
                      isOn: $model.settings.room, tint: tint)
                .disabled(s.track == .musicApp)
                .opacity(s.track == .musicApp ? 0.45 : 1)
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

    private func session(_ s: Settings, _ tint: Color) -> some View {
        SettingsSection(title: "Session", summary: s.limit > 0 ? "\(s.limit) minutes" : "No time limit", isOpen: open("session")) {
            ChipPicker(title: "Stop after", choices: Settings.limits.map { Choice(value: $0, name: $0 == 0 ? "No limit" : "\($0) min") },
                       selection: $model.settings.limit, tint: tint)
            Note(text: "Sound keeps playing when you lock your phone or switch to another app.")
        }
    }
}
