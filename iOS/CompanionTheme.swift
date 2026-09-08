import SwiftUI
import UIKit

/// The Aura palette on iOS. Values are canonical in `brand/design-tokens.md`;
/// keep this in step with `BrandColors` in `Sources/Aura/Brand.swift`.
enum CompanionBrand {
    static let scrobbleRed = Color(red: 1.0, green: 70.0 / 255.0, blue: 75.0 / 255.0)

    // The Aura sweep. Warm entry through to cool exit.
    static let peach = Color(hex: "#FFC49B")
    static let blush = Color(hex: "#FF9AA8")
    static let lilac = Color(hex: "#A78BFA")
    static let indigo = Color(hex: "#5B5BF5")

    // Neutrals, tinted very slightly violet.
    static let ink = Color(hex: "#121219")
    static let graphite = Color(hex: "#55546B")
    static let haze = Color(hex: "#F7F6FB")
    static let dusk = Color(hex: "#0F0F17")
    static let onyx = Color(hex: "#17171F")
    static let vapor = Color(hex: "#A9A7BC")

    /// The companion is dark-first, matching the Mac app's menu-bar surfaces.
    static let canvas = dusk
    static let surface = onyx
    static let secondaryText = vapor
    static let hairline = Color.white.opacity(0.08)

    // Status colors resolve per appearance so body text clears WCAG AA either way.
    static let success = adaptive(light: "#0F7A43", dark: "#3FD483")
    static let warning = adaptive(light: "#8A5300", dark: "#F0A93B")
    static let error = adaptive(light: "#B3242E", dark: "#FF7A85")
    static let neutral = adaptive(light: "#5A5970", dark: "#A9A7BC")

    /// The halo sweep. `angle` drives the brand motion signature.
    static func sweep(angle: Angle = .zero) -> AngularGradient {
        AngularGradient(
            gradient: Gradient(stops: [
                .init(color: peach, location: 0.00),
                .init(color: blush, location: 0.22),
                .init(color: lilac, location: 0.48),
                .init(color: indigo, location: 0.74),
                .init(color: peach, location: 1.00),
            ]),
            center: .center,
            angle: angle
        )
    }

    private static func adaptive(light: String, dark: String) -> Color {
        Color(
            uiColor: UIColor { traits in
                UIColor(traits.userInterfaceStyle == .dark ? Color(hex: dark) : Color(hex: light))
            })
    }
}

extension Color {
    /// Six-digit hex. Traps on a malformed literal, which is what we want for the
    /// compile-time constants above.
    init(hex: String) {
        var clean = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if clean.hasPrefix("#") { clean.removeFirst() }
        guard clean.count == 6, let value = UInt64(clean, radix: 16) else {
            preconditionFailure("Malformed brand color literal: \(hex)")
        }
        self.init(
            red: Double((value & 0xFF0000) >> 16) / 255,
            green: Double((value & 0x00FF00) >> 8) / 255,
            blue: Double(value & 0x0000FF) / 255
        )
    }
}

/// Spacing and radius scales that mirror `BrandSpacing` and `BrandRadius` on
/// macOS so both apps share one rhythm.
enum CompanionSpacing {
    static let xs: CGFloat = 6
    static let sm: CGFloat = 10
    static let md: CGFloat = 16
    static let lg: CGFloat = 24
    static let xl: CGFloat = 32
}

enum CompanionRadius {
    static let sm: CGFloat = 12
    static let md: CGFloat = 18
    static let lg: CGFloat = 26
}

/// The widest comfortable measure for the companion's single-column layouts.
/// Keeps onboarding and detail content from stretching edge to edge on iPad.
enum CompanionLayout {
    static let readableWidth: CGFloat = 560
}

/// The Aura halo, matching `BrandMark` on macOS so the mark reads as one identity
/// across platforms. The glow is part of the mark, not a shadow behind it.
struct CompanionBrandMark: View {
    var sweep: Angle = .zero

    // Proportions match brand/aura-symbol.svg on its 64-point canvas.
    private let ringDiameter: CGFloat = 46.0 / 64.0
    private let ringWidth: CGFloat = 5.5 / 64.0
    private let glowWidth: CGFloat = 8.0 / 64.0
    private let glowBlur: CGFloat = 3.4 / 64.0
    private let coreDiameter: CGFloat = 11.0 / 64.0

    var body: some View {
        GeometryReader { proxy in
            let size = min(proxy.size.width, proxy.size.height)
            let shading = CompanionBrand.sweep(angle: sweep)
            ZStack {
                Circle()
                    .stroke(shading, lineWidth: size * glowWidth)
                    .frame(width: size * ringDiameter, height: size * ringDiameter)
                    .blur(radius: size * glowBlur)
                    .opacity(0.45)
                Circle()
                    .stroke(shading, lineWidth: size * ringWidth)
                    .frame(width: size * ringDiameter, height: size * ringDiameter)
                Circle()
                    .fill(shading)
                    .frame(width: size * coreDiameter, height: size * coreDiameter)
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityLabel("Aura")
    }
}

/// The brand motion signature: the halo's gradient sweeps slowly around the ring
/// while something is playing. Freezes in place — never hides — under Reduce Motion.
struct SweepingCompanionBrandMark: View {
    var isPlaying = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// One revolution every 12 seconds.
    private static let period: TimeInterval = 12

    var body: some View {
        TimelineView(
            .animation(
                minimumInterval: reduceMotion || !isPlaying ? 1_000_000 : 1.0 / 30.0,
                paused: reduceMotion || !isPlaying
            )
        ) { context in
            CompanionBrandMark(sweep: sweepAngle(at: context.date))
        }
    }

    private func sweepAngle(at date: Date) -> Angle {
        guard isPlaying, !reduceMotion else { return .zero }
        let phase = date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: Self.period)
        return .degrees(phase / Self.period * 360)
    }
}

extension View {
    func companionCanvas() -> some View {
        scrollContentBackground(.hidden)
            .background(CompanionBrand.canvas.ignoresSafeArea())
    }

    /// The companion's standard surface: a translucent material card with
    /// continuous rounding and a tinted glow instead of a hairline border.
    func companionCard(padding: CGFloat = CompanionSpacing.md) -> some View {
        self
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: CompanionRadius.lg, style: .continuous))
            .shadow(color: CompanionBrand.indigo.opacity(0.10), radius: 12, y: 4)
    }

    /// Constrains a single column of content to a comfortable reading width and
    /// centers it, which matters on iPad and landscape iPhone.
    func companionReadableColumn() -> some View {
        frame(maxWidth: CompanionLayout.readableWidth)
            .frame(maxWidth: .infinity)
    }
}
