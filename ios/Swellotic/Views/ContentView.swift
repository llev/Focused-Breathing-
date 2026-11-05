import SwiftUI

struct ContentView: View {
    @ObservedObject var model: AppModel
    @State private var showSettings = false
    @State private var showSplash = true
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        ZStack {
            Color.night.ignoresSafeArea()
            SceneView(model: model)

            VStack(spacing: 12) {
                topBar
                Spacer(minLength: 0)
                PhaseLabel(model: model)
                    .opacity(showSplash ? 0 : 1)
                    .animation(.easeInOut(duration: 0.6), value: showSplash)
                Spacer(minLength: 0)
                footer
            }
            .padding(16)

            if showSplash {
                SplashView { showSplash = false }
            }
        }
        .sheet(isPresented: $showSettings) {
            SettingsSheet(model: model)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
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
            if model.running {
                Text(model.elapsed)
                    .font(.system(size: 14, weight: .medium).monospacedDigit())
                    .padding(.horizontal, 12)
                    .padding(.vertical, 5)
                    .frostedCapsule()
                    .accessibilityLabel("Time so far")
                    .accessibilityValue(model.elapsed)
            }
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
            PlayerBar(model: model) { showSettings = true }
        }
    }
}

/// "In" or "Out", and the optional countdown.
struct PhaseLabel: View {
    @ObservedObject var model: AppModel

    var body: some View {
        TimelineView(.animation(minimumInterval: 0.1)) { _ in
            let frame = model.frame()
            VStack(spacing: 10) {
                if model.settings.showWords {
                    Text(frame.phase.isIn ? "In" : "Out")
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
                }
            }
            .accessibilityHidden(true)
        }
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
                MixSlider(title: "Music", value: musicApp ? "In your music app" : "\(Int(s.musicVolume))%",
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
