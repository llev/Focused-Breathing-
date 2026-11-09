import SwiftUI

/// The frosted glass look. On iOS 26 it uses Apple's Liquid Glass; earlier versions use a blurred material.
struct Frosted<S: Shape>: ViewModifier {
    let shape: S

    func body(content: Content) -> some View {
        #if compiler(>=6.2)
        if #available(iOS 26.0, *) {
            content.glassEffect(.regular, in: shape)
        } else {
            fallback(content)
        }
        #else
        fallback(content)
        #endif
    }

    private func fallback(_ content: Content) -> some View {
        content
            .background(Color(hex: 0x1A1524, opacity: 0.62), in: shape)
            .background(.ultraThinMaterial, in: shape)
            .overlay(shape.stroke(Color.white.opacity(0.14), lineWidth: 1))
    }
}

extension View {
    func frosted(cornerRadius: CGFloat) -> some View { modifier(Frosted(shape: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))) }
    func frostedCapsule() -> some View { modifier(Frosted(shape: Capsule())) }

    /// Keeps light text readable over the moving scenes.
    func sceneShadow() -> some View { shadow(color: .black.opacity(0.55), radius: 10, y: 1) }
}

/// Lays out chips in rows, wrapping onto a new row when one fills up.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0, widest: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > 0 && x + size.width > width {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
            widest = max(widest, x - spacing)
        }
        return CGSize(width: proposal.width ?? widest, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowHeight: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > bounds.minX && x + size.width > bounds.maxX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            view.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

struct Choice<Value: Hashable>: Identifiable {
    let value: Value
    let name: String
    var id: Value { value }
}

/// A set of chips where one is chosen, like radio buttons.
struct ChipPicker<Value: Hashable>: View {
    let title: String?
    let choices: [Choice<Value>]
    @Binding var selection: Value
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let title { Text(title).font(.subheadline.weight(.semibold)) }
            FlowLayout(spacing: 7) {
                ForEach(choices) { choice in
                    let chosen = choice.value == selection
                    Button {
                        selection = choice.value
                    } label: {
                        Text(choice.name)
                            .font(.system(size: 15, weight: chosen ? .semibold : .medium))
                            .padding(.horizontal, 14)
                            .frame(minHeight: 44)
                            .foregroundStyle(chosen ? Color(hex: 0x17121F) : .white)
                            .background(chosen ? tint : Color.well, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(chosen ? .isSelected : [])
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(title ?? "")
    }
}

/// A switch between a few options, styled like the web app's: labels can wrap onto two lines, and the chosen option's
/// background fills the whole height, so nothing is squashed or cut off on narrow screens.
struct SegmentedChoice<Value: Hashable>: View {
    let title: String
    let choices: [Choice<Value>]
    @Binding var selection: Value

    var body: some View {
        HStack(spacing: 2) {
            ForEach(choices) { choice in
                let chosen = choice.value == selection
                Button {
                    withAnimation(.snappy(duration: 0.2)) { selection = choice.value }
                } label: {
                    Text(choice.name)
                        .font(.system(size: 15, weight: .semibold))
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .foregroundStyle(chosen ? Color(hex: 0x17121F) : Color.soft)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 6)
                        .frame(maxWidth: .infinity, minHeight: 44, maxHeight: .infinity)
                        .background {
                            if chosen {
                                RoundedRectangle(cornerRadius: 11, style: .continuous)
                                    .fill(.white)
                                    .shadow(color: .black.opacity(0.25), radius: 3.5, y: 2)
                            }
                        }
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(chosen ? .isSelected : [])
            }
        }
        // Every option takes the height of the tallest, so the chosen background always fills the switch.
        .fixedSize(horizontal: false, vertical: true)
        .padding(3)
        .background(Color.well, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .accessibilityElement(children: .contain)
        .accessibilityLabel(title)
    }
}

/// A collapsible settings card. When closed, it shows its current setting.
struct SettingsSection<Content: View>: View {
    let title: String
    let summary: String
    @Binding var isOpen: Bool
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.snappy(duration: 0.25)) { isOpen.toggle() }
            } label: {
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(title).font(.system(size: 17, weight: .semibold))
                        if !isOpen {
                            Text(summary).font(.system(size: 15)).foregroundStyle(Color.soft).multilineTextAlignment(.leading)
                        }
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color.soft)
                        .rotationEffect(.degrees(isOpen ? 180 : 0))
                }
                .padding(.horizontal, 18)
                .frame(minHeight: 58)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityValue(isOpen ? "Open" : summary)
            .accessibilityHint(isOpen ? "Closes this section" : "Opens this section")

            if isOpen {
                VStack(alignment: .leading, spacing: 18) { content }
                    .padding(.horizontal, 18)
                    .padding(.bottom, 18)
                    .padding(.top, 2)
                    .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .frosted(cornerRadius: 22)
    }
}

/// A switch with a title and an optional explanation.
struct ToggleRow: View {
    let title: String
    var detail: String?
    @Binding var isOn: Bool
    let tint: Color

    var body: some View {
        Toggle(isOn: $isOn) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.body.weight(.medium))
                if let detail { Text(detail).font(.subheadline).foregroundStyle(Color.soft) }
            }
        }
        .tint(tint)
        .frame(minHeight: 44)
    }
}

struct Note: View {
    let text: String
    var body: some View {
        Text(text).font(.subheadline).foregroundStyle(Color.soft).fixedSize(horizontal: false, vertical: true)
    }
}
