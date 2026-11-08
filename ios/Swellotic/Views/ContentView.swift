import SwiftUI

struct ContentView: View {
    @ObservedObject var model: AppModel
    @State private var showSettings = false
    @State private var showSession = false
    @State private var showSplash = true
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.horizontalSizeClass) private var sizeClass

    var body: some View {
        ZStack {
            Color.night.ignoresSafeArea()
            SceneView(model: model)

            VStack(spacing: 12) {
                topBar
                Spacer(minLength: 0)
                PhaseLabel(model: model) { showSession = true }
                    .opacity(showSplash ? 0 : 1)
                    .animation(.easeInOut(duration: 0.6), value: showSplash)
                    // On iPad and Mac, Session is a popover by its button. On iPhone it becomes a sheet.
                    .popover(isPresented: $showSession) {
                        SessionSheet(model: model) { showSession = false }
                            .frame(minWidth: sizeClass == .regular ? 400 : nil, minHeight: sizeClass == .regular ? 560 : nil)
                            .presentationCompactAdaptation(.sheet)
                            .presentationDetents([.medium, .large])
                            .presentationDragIndicator(.visible)
                    }
                Spacer(minLength: 0)
                footer
            }
            .padding(16)

            if showSplash {
                SplashView { showSplash = false }
            }
        }
        // On iPad and Mac, Settings is a side panel, so the scene and player bar stay in view, as in the web app on wide
        // screens. On iPhone the same panel becomes a sheet from the bottom.
        .inspector(isPresented: $showSettings) {
            SettingsSheet(model: model) { showSettings = false }
                .inspectorColumnWidth(min: 340, ideal: 400, max: 480)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
        #if DEBUG
        // Lets GitHub Actions open a panel by itself for screenshots, after the launch screen. Never in release builds.
        .task {
            guard let panel = ProcessInfo.processInfo.environment["SWELLOTIC_OPEN"] else { return }
            try? await Task.sleep(for: .seconds(3))
            if panel == "settings" { showSettings = true } else if panel == "session" { showSession = true }
        }
        #endif
        .onChange(of: scenePhase) { _, phase in model.scenePhaseChanged(phase) }
        .preferredColorScheme(.dark)
        .tint(model.tint)
    }

    private var topBar: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Swellotic").font(.system(size: 17, weight: .semibold))
                Text("Breathe. Listen. Focus.").font(.system(size: 14))
            }
            .sceneShadow()
            .accessibilityElement(children: .combine)
            Spacer()
        }
    }

    private var footer: some View {
        VStack(spacing: 10) {
            if !model.status.isEmpty {
                Text(model.status)
                    .font(.system(size: 15, weight: .medium))
                    .multilineTextAlignment(.center)
                    .sceneShadow()
            }
            if model.showResume {
                Button("Sound paused. Tap to resume.") { model.tapToResume() }
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 18)
                    .frame(minHeight: 44)
                    .frostedCapsule()
            }
            if model.settings.track == .classical {
                NowPlayingStrip(model: model, library: model.library)
            }
            PlayerBar(model: model) { showSettings.toggle() }
        }
    }
}

/// "In", "Out" or "Rest", the optional countdown, and the session button, which doubles as the clock while playing.
struct PhaseLabel: View {
    @ObservedObject var model: AppModel
    let openSession: () -> Void

    var body: some View {
        TimelineView(.animation(minimumInterval: 0.1)) { _ in
            let frame = model.frame()
            VStack(spacing: 10) {
                if model.settings.showWords {
                    Text(model.running && model.resting ? "Rest" : frame.phase.isIn ? "In" : "Out")
                        .font(.system(size: 112, weight: .light, design: .rounded))
                        .minimumScaleFactor(0.5)
                        .lineLimit(1)
                        .sceneShadow()
                }
                if model.settings.countdown {
                    let left = max(0, Int(ceil(frame.phase.end - frame.time)))
                    Text("\(left) s left  ·  \(String(format: "%.1f", frame.phase.bpm)) breaths/min")
                        .font(.system(size: 15, weight: .medium).monospacedDigit())
                        .padding(.horizontal, 14)
                        .padding(.vertical, 5)
                        .frostedCapsule()
                        .accessibilityHidden(true)
                }
                Button(action: openSession) {
                    HStack(spacing: 7) {
                        Image(systemName: "timer").font(.system(size: 15, weight: .semibold))
                        Text(model.sessionText).font(.system(size: 15, weight: .medium).monospacedDigit())
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .frame(minHeight: 44)
                    .frostedCapsule()
                }
                .buttonStyle(PressableStyle())
                .accessibilityLabel("Session")
                .accessibilityValue(model.sessionText)
            }
        }
    }
}

/// The Classical mix piece, with previous, next and repeat-one, above the player bar.
struct NowPlayingStrip: View {
    @ObservedObject var model: AppModel
    @ObservedObject var library: ClassicalLibrary

    var body: some View {
        let s = model.settings
        let piece = library.pieces.indices.contains(s.piece) ? library.pieces[s.piece] : nil
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(piece?.heading ?? "Classical mix")
                    .font(.system(size: 15, weight: .semibold))
                    .lineLimit(1)
                HStack(spacing: 8) {
                    if !model.pieceTime.isEmpty { Text(model.pieceTime).monospacedDigit() }
                    Text(piece?.performer ?? "")
                }
                .font(.system(size: 13))
                .foregroundStyle(Color.soft)
                .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
            stripButton("backward.end.fill", label: "Previous piece") { model.skipPiece(-1) }
            stripButton("forward.end.fill", label: "Next piece") { model.skipPiece(1) }
            stripButton("repeat.1", label: "Repeat this piece", on: s.repeatOne) { model.settings.repeatOne.toggle() }
        }
        .padding(.leading, 16)
        .padding(.trailing, 8)
        .padding(.vertical, 6)
        .frame(maxWidth: 580)
        .frosted(cornerRadius: 22)
    }

    private func stripButton(_ icon: String, label: String, on: Bool? = nil, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(on == true ? model.settings.palette.onTint : .white)
                .frame(width: 44, height: 44)
                .background(on == true ? model.settings.palette.tint : Color.well, in: Circle())
        }
        .buttonStyle(PressableStyle())
        .accessibilityLabel(label)
        .accessibilityAddTraits(on == true ? .isSelected : [])
    }
}

/// Always on screen: play, the two volumes and Settings.
struct PlayerBar: View {
    @ObservedObject var model: AppModel
    let openSettings: () -> Void

    var body: some View {
        let s = model.settings
        let musicApp = s.track == .musicApp
        HStack(spacing: 14) {
            Button(action: model.toggle) {
                Image(systemName: model.running ? "stop.fill" : "play.fill")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundStyle(s.palette.onTint)
                    .frame(width: 64, height: 64)
                    .background(s.palette.tint, in: Circle())
                    .shadow(color: .black.opacity(0.3), radius: 10, y: 6)
            }
            .buttonStyle(PressableStyle())
            .accessibilityLabel(model.running ? "Stop" : "Start")

            VStack(spacing: 4) {
                MixSlider(title: "Breath", value: s.breathVolume == 0 ? "Silent" : "\(Int(s.breathVolume))%",
                          number: $model.settings.breathVolume, disabled: false)
                MixSlider(title: "Sounds", value: musicApp ? "In your music app" : "\(Int(s.musicVolume))%",
                          number: $model.settings.musicVolume, disabled: musicApp)
            }

            Button(action: openSettings) {
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 46, height: 46)
                    .background(Color.well, in: Circle())
            }
            .buttonStyle(PressableStyle())
            .accessibilityLabel("Settings")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: 580)
        .frosted(cornerRadius: 30)
        .shadow(color: .black.opacity(0.35), radius: 25, y: 18)
    }
}

struct MixSlider: View {
    let title: String
    let value: String
    @Binding var number: Double
    let disabled: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(title).font(.system(size: 14, weight: .semibold))
                Spacer(minLength: 8)
                Text(value).font(.system(size: 14).monospacedDigit()).foregroundStyle(Color.soft).lineLimit(1)
            }
            Slider(value: $number, in: 0...100, step: 1)
                .disabled(disabled)
                .accessibilityLabel(title)
                .accessibilityValue(value)
        }
    }
}

struct PressableStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.93 : 1)
            .animation(.easeOut(duration: 0.16), value: configuration.isPressed)
    }
}
