import SwiftUI

/// The moving scene behind everything. Every scene draws from the same breath level, so sound and picture stay together.
/// With Reduce Motion turned on, the scene becomes a gentle colour fade.
struct SceneView: View {
    @ObservedObject var model: AppModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60)) { _ in
            let now = AudioController.hostNow()
            let level = model.frame(at: now).level
            let palette = model.settings.palette
            let scene = model.settings.scene
            let still = reduceMotion
            Canvas { context, size in
                Scenes.draw(scene, palette: palette, level: level, time: now, still: still, in: &context, size: size)
            }
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }
}

/// Drawing for each scene, ported from app.js. `time` drives slow drifting; `level` is how full the breath is.
enum Scenes {
    private struct Blob { let x, sx, sy, p, r: Double }

    private static let blobs: [Blob] = (0..<7).map { i in
        let d = Double(i)
        return Blob(x: 0.15 + d * 0.115, sx: 0.11 + d * 0.023, sy: 0.07 + Double(i % 4) * 0.03, p: d * 1.9, r: 0.13 + Double(i % 3) * 0.035)
    }

    static func draw(_ scene: SceneStyle, palette: Palette, level: Double, time t: Double, still: Bool,
                     in context: inout GraphicsContext, size: CGSize) {
        let w = size.width, h = size.height
        guard w > 0, h > 0 else { return }
        let all = Path(CGRect(origin: .zero, size: size))
        context.fill(all, with: .linearGradient(Gradient(colors: palette.ground), startPoint: .zero, endPoint: CGPoint(x: 0, y: h)))

        if still {
            context.fill(all, with: .color(palette.colors[0].opacity(0.2 + level * 0.7)))
            return
        }

        switch scene {
        case .lava: lava(palette, level, t, &context, w, h)
        case .bloom: bloom(palette, level, t, &context, w, h)
        case .rings: rings(palette, level, t, &context, w, h)
        case .aurora: aurora(palette, level, t, &context, w, h)
        case .tide: tide(palette, level, t, &context, w, h)
        }
        context.fill(all, with: .color(Color(red: 10 / 255, green: 8 / 255, blue: 16 / 255, opacity: 0.16)))
    }

    /// Blobs that merge like a lava lamp: drawn blurred, then cut off sharply, then filled with the palette.
    private static func lava(_ p: Palette, _ level: Double, _ t: Double, _ context: inout GraphicsContext, _ w: Double, _ h: Double) {
        let span = min(w, h)
        let size = 0.72 + level * 0.62
        var layer = context
        layer.clipToLayer { mask in
            // Filters apply last-added first: blur, then threshold, then a slight softening of the edge.
            mask.addFilter(.blur(radius: 1.5))
            mask.addFilter(.alphaThreshold(min: 0.5))
            mask.addFilter(.blur(radius: span * 0.06))
            mask.drawLayer { blobsLayer in
                for b in blobs {
                    let x = (b.x + sin(t * b.sx + b.p) * 0.1) * w
                    let y = (0.5 + sin(t * b.sy + b.p * 1.7) * 0.42) * h
                    let r = b.r * size * span
                    blobsLayer.fill(Path(ellipseIn: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2)), with: .color(.white))
                }
            }
        }
        layer.fill(Path(CGRect(x: 0, y: 0, width: w, height: h)),
                   with: .linearGradient(Gradient(colors: p.colors), startPoint: .zero, endPoint: CGPoint(x: 0, y: h)))
    }

    private static func bloom(_ p: Palette, _ level: Double, _ t: Double, _ context: inout GraphicsContext, _ w: Double, _ h: Double) {
        let cx = w / 2, cy = h * 0.47, unit = min(w, h)
        let dist = unit * (0.05 + level * 0.2), r = unit * (0.11 + level * 0.14)
        var c = context
        c.blendMode = .screen
        c.opacity = 0.46
        for i in 0..<8 {
            let a = Double(i) / 8 * 2 * .pi + t * 0.05 + level * 0.5
            let x = cx + cos(a) * dist, y = cy + sin(a) * dist
            c.fill(Path(ellipseIn: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2)), with: .color(p.colors[i % 3]))
        }
    }

    private static func rings(_ p: Palette, _ level: Double, _ t: Double, _ context: inout GraphicsContext, _ w: Double, _ h: Double) {
        let cx = w / 2, cy = h * 0.47, unit = hypot(w, h) * 0.3
        for i in stride(from: 5, through: 0, by: -1) {
            var c = context
            c.opacity = 0.34 + Double(5 - i) * 0.1
            let r = unit * (0.14 + Double(i) * 0.16) * (0.5 + level * 0.62) * (1 + sin(t * 0.4 + Double(i)) * 0.015)
            c.fill(Path(ellipseIn: CGRect(x: cx - r, y: cy - r, width: r * 2, height: r * 2)), with: .color(p.colors[i % 3]))
        }
    }

    private static func aurora(_ p: Palette, _ level: Double, _ t: Double, _ context: inout GraphicsContext, _ w: Double, _ h: Double) {
        var c = context
        c.blendMode = .screen
        for (i, colour) in p.colors.enumerated() {
            let d = Double(i)
            let top = h * (0.62 - level * 0.46) + d * h * 0.05
            var path = Path()
            path.move(to: CGPoint(x: 0, y: h))
            var x = 0.0
            while x <= w + 12 {
                path.addLine(to: CGPoint(x: x, y: top + sin(x / (170 + d * 60) + t * (0.22 + d * 0.07) + d * 2) * h * 0.07))
                x += 12
            }
            path.addLine(to: CGPoint(x: w, y: h))
            path.closeSubpath()
            let gradient = Gradient(stops: [.init(color: colour.opacity(0), location: 0),
                                            .init(color: colour.opacity(0.55), location: 0.3),
                                            .init(color: colour.opacity(0), location: 1)])
            c.fill(path, with: .linearGradient(gradient, startPoint: CGPoint(x: 0, y: top - h * 0.1), endPoint: CGPoint(x: 0, y: top + h * 0.62)))
        }
    }

    private static func tide(_ p: Palette, _ level: Double, _ t: Double, _ context: inout GraphicsContext, _ w: Double, _ h: Double) {
        let y = h * (0.86 - level * 0.68)
        wave(&context, w, h, y, 7, 150, t * 0.38, p.colors[0])
        wave(&context, w, h, y + 18, 5, 95, -t * 0.5, p.colors[1])
    }

    private static func wave(_ context: inout GraphicsContext, _ w: Double, _ h: Double, _ y: Double, _ amp: Double,
                             _ length: Double, _ shift: Double, _ colour: Color) {
        var path = Path()
        path.move(to: CGPoint(x: 0, y: h))
        var x = 0.0
        while x <= w + 12 {
            path.addLine(to: CGPoint(x: x, y: y + sin(x / length + shift) * amp))
            x += 12
        }
        path.addLine(to: CGPoint(x: w, y: h))
        path.closeSubpath()
        context.fill(path, with: .color(colour))
    }
}
