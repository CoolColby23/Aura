import SwiftUI

/// How a surface separates itself from the canvas behind it.
///
/// Content never uses Liquid Glass — glass belongs to the controls and
/// navigation that float above content. A surface is a quiet fill one step
/// lighter than the canvas; only `raised` adds the brand's tinted glow.
enum AuraSurfaceStyle {
    /// A group of rows, a chart, a settings block. The default.
    case plain
    /// The one surface on a page that should draw the eye. Adds a tinted glow.
    case raised
    /// A block nested inside another surface, or a callout on the canvas. A
    /// faint tint, no edge.
    case inset
}

extension View {
    func auraSurface(_ style: AuraSurfaceStyle = .plain, radius: CGFloat = BrandRadius.md) -> some View {
        modifier(AuraSurfaceModifier(style: style, radius: radius))
    }

    @ViewBuilder
    func auraButton(prominent: Bool = false) -> some View {
        if #available(macOS 26, *) {
            if prominent {
                buttonStyle(.glassProminent)
            } else {
                buttonStyle(.glass)
            }
        } else {
            if prominent { buttonStyle(.borderedProminent) } else { buttonStyle(.bordered) }
        }
    }

    /// The page canvas: the theme's canvas color, lit softly from the top
    /// corner. One light source, never a pattern of blobs.
    func auraPanelBackground() -> some View {
        modifier(AuraPanelBackground())
    }

    /// Applies the brand's tracked all-caps label treatment.
    func auraEyebrow() -> some View {
        font(BrandTypography.eyebrow)
            .tracking(1.05)
            .textCase(.uppercase)
    }
}

private struct AuraSurfaceModifier: ViewModifier {
    let style: AuraSurfaceStyle
    let radius: CGFloat
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.appTheme) private var theme

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        switch style {
        case .inset:
            content.background(theme.primaryColor.opacity(colorScheme == .dark ? 0.08 : 0.045), in: shape)
        case .plain, .raised:
            let glow = BrandElevation.low.color(tint: theme.primaryColor, scheme: colorScheme)
            content
                .background {
                    shape
                        .fill(theme.surface(for: colorScheme, elevated: true))
                        .overlay { shape.strokeBorder(BrandColors.hairline, lineWidth: 1) }
                        .shadow(
                            color: style == .raised ? glow : .clear,
                            radius: BrandElevation.low.radius,
                            y: BrandElevation.low.y
                        )
                }
        }
    }
}

private struct AuraPanelBackground: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.appTheme) private var theme

    func body(content: Content) -> some View {
        content.background {
            ZStack {
                theme.canvas(for: colorScheme)
                RadialGradient(
                    colors: [theme.secondaryColor.opacity(colorScheme == .dark ? 0.12 : 0.10), .clear],
                    center: .topTrailing,
                    startRadius: 0,
                    endRadius: 720
                )
                RadialGradient(
                    colors: [theme.primaryColor.opacity(colorScheme == .dark ? 0.08 : 0.05), .clear],
                    center: .bottomLeading,
                    startRadius: 0,
                    endRadius: 640
                )
            }
            .ignoresSafeArea()
        }
    }
}
