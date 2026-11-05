import SwiftUI

/// The launch screen from the web app: the sun rises behind the swell like a breath in, the name settles letter by letter,
/// then the tagline arrives one word at a time. About two and a half seconds; a tap skips it. With Reduce Motion, it simply fades.
struct SplashView: View {
    let onFinish: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown = false
    @State private var leaving = false

    private let name = Array("Swellotic")
    private let words = ["Breathe.", "Listen.", "Focus."]
    private let ease = Animation.timingCurve(0.2, 0.8, 0.2, 1, duration: 0.8)

    var body: some View {
        let visible = shown || reduceMotion
        ZStack {
            RadialGradient(colors: [Color(hex: 0x2A1238), .night], center: UnitPoint(x: 0.5, y: 0.4), startRadius: 0, endRadius: 520)
                .ignoresSafeArea()
            VStack(spacing: 0) {
                SplashArt(shown: visible, animated: !reduceMotion)
                    .frame(width: 200, height: 125)
                    .padding(.bottom, 6)
                HStack(spacing: 0) {
                    ForEach(name.indices, id: \.self) { i in
                        Text(String(name[i]))
                            .opacity(visible ? 1 : 0)
                            .offset(y: visible ? 0 : 18)
                            .blur(radius: visible ? 0 : 6)
                            .animation(reduceMotion ? nil : ease.delay(0.5 + Double(i) * 0.045), value: shown)
                    }
                }
                .font(.system(size: 60, weight: .light, design: .rounded))
                HStack(spacing: 8) {
                    ForEach(words.indices, id: \.self) { i in
                        Text(words[i].uppercased())
                            .opacity(visible ? 1 : 0)
                            .offset(y: visible ? 0 : 6)
                            .animation(reduceMotion ? nil : .easeOut(duration: 0.6).delay(1.05 + Double(i) * 0.2), value: shown)
                    }
                }
                .font(.system(size: 13, weight: .medium))
                .tracking(3.4)
                .foregroundStyle(Color(hex: 0xFFB27A))
                .padding(.top, 14)
            }
            .scaleEffect(leaving ? 1.04 : 1)
            .blur(radius: leaving ? 4 : 0)
        }
        .opacity(leaving ? 0 : 1)
        .contentShape(Rectangle())
        .onTapGesture { leave(quickly: true) }
        .task {
            shown = true
            try? await Task.sleep(for: .milliseconds(2100))
            leave(quickly: false)
        }
        .accessibilityHidden(true)
    }

    private func leave(quickly: Bool) {
        guard !leaving else { return }
        withAnimation(quickly ? .easeOut(duration: 0.3) : .timingCurve(0.4, 0, 0.2, 1, duration: 0.5)) { leaving = true }
        Task {
            try? await Task.sleep(for: .milliseconds(quickly ? 300 : 500))
            onFinish()
        }
    }
}

/// The app icon's sun and waves, drawn on the same 160 by 100 grid as the web launch screen.
struct SplashArt: View {
    let shown: Bool
    let animated: Bool

    var body: some View {
        GeometryReader { geo in
            let s = geo.size.width / 160
            ZStack {
                Circle()
                    .fill(RadialGradient(colors: [Color(hex: 0xFFB27A, opacity: 0.5), Color(hex: 0xFFB27A, opacity: 0)],
                                         center: .center, startRadius: 0, endRadius: 50 * s))
                    .frame(width: 100 * s, height: 100 * s)
                    .scaleEffect(shown ? 1 : 0.4)
                    .opacity(shown ? 1 : 0)
                    .position(x: 80 * s, y: 50 * s)
                    .animation(animated ? .timingCurve(0.2, 0.8, 0.2, 1, duration: 1.6).delay(0.1) : nil, value: shown)

                ZStack {
                    Circle()
                        .fill(LinearGradient(colors: [Color(hex: 0xFFC58A), Color(hex: 0xFF7A59)], startPoint: .top, endPoint: .bottom))
                        .frame(width: 48 * s, height: 48 * s)
                        .offset(y: shown ? 0 : 33.6 * s)
                        .position(x: 80 * s, y: 50 * s)
                        .animation(animated ? .timingCurve(0.22, 0.9, 0.25, 1, duration: 1.2).delay(0.15) : nil, value: shown)
                }
                .frame(width: geo.size.width, height: geo.size.height)
                .mask(SplashSea())

                SplashWave(first: true)
                    .trim(from: 0, to: shown ? 1 : 0)
                    .stroke(Color(hex: 0xE8487E), style: StrokeStyle(lineWidth: 3.2 * s, lineCap: .round))
                    .animation(animated ? .timingCurve(0.45, 0, 0.2, 1, duration: 1).delay(0.2) : nil, value: shown)
                SplashWave(first: false)
                    .trim(from: 0, to: shown ? 1 : 0)
                    .stroke(Color(hex: 0xFFB347), style: StrokeStyle(lineWidth: 2.6 * s, lineCap: .round))
                    .opacity(0.85)
                    .animation(animated ? .timingCurve(0.45, 0, 0.2, 1, duration: 1).delay(0.38) : nil, value: shown)
            }
        }
    }
}

/// The two waves from the web launch screen's SVG, with its smooth curve commands written out in full.
struct SplashWave: Shape {
    let first: Bool

    func path(in rect: CGRect) -> Path {
        let sx = rect.width / 160, sy = rect.height / 100
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: rect.minX + x * sx, y: rect.minY + y * sy) }
        var path = Path()
        if first {
            path.move(to: p(8, 59))
            path.addCurve(to: p(56, 59), control1: p(24, 53), control2: p(40, 53))
            path.addCurve(to: p(104, 59), control1: p(72, 65), control2: p(88, 66))
            path.addCurve(to: p(152, 58), control1: p(120, 52), control2: p(136, 52))
        } else {
            path.move(to: p(20, 70))
            path.addCurve(to: p(62, 70), control1: p(34, 65), control2: p(48, 65))
            path.addCurve(to: p(104, 70), control1: p(76, 75), control2: p(90, 76))
            path.addCurve(to: p(140, 69), control1: p(118, 64), control2: p(128, 65))
        }
        return path
    }
}

/// Everything above the first wave, so the sun rises from behind it.
struct SplashSea: Shape {
    func path(in rect: CGRect) -> Path {
        var path = SplashWave(first: true).path(in: rect)
        let sx = rect.width / 160, sy = rect.height / 100
        path.addLine(to: CGPoint(x: rect.minX + 160 * sx, y: rect.minY + 58 * sy))
        path.addLine(to: CGPoint(x: rect.minX + 160 * sx, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + 59 * sy))
        path.closeSubpath()
        return path
    }
}
