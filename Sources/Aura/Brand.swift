import AppKit
import SwiftUI

/// The Aura palette. Values are canonical in `brand/design-tokens.md`; change them
/// there first, then here and in `iOS/CompanionTheme.swift`.
enum BrandColors {
    // The Aura sweep. Warm entry through to cool exit; used for the halo mark and
    // live playback state, and nowhere else.
    static let peach = Color(hex: "#FFC49B")!
    static let blush = Color(hex: "#FF9AA8")!
    static let lilac = Color(hex: "#A78BFA")!
    static let indigo = Color(hex: "#5B5BF5")!

    /// Indigo dark enough to serve as body text on a light surface (6.05:1 on Haze).
    static let indigoText = Color(hex: "#4B45E0")!

    // Neutrals, tinted very slightly violet so they sit under the sweep cleanly.
    static let ink = Color(hex: "#121219")!
    static let graphite = Color(hex: "#55546B")!
    static let haze = Color(hex: "#F7F6FB")!
    static let veil = Color.white
    static let dusk = Color(hex: "#0F0F17")!
    static let onyx = Color(hex: "#17171F")!
    static let vapor = Color(hex: "#A9A7BC")!

    /// The four sweep stops in order, closed back to Peach so an angular gradient
    /// has no seam.
    static let sweepStops: [Color] = [peach, blush, lilac, indigo, peach]

    /// The halo sweep as an angular gradient. `angle` drives the motion signature.
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

    // Status colors resolve per appearance so body-size text clears WCAG AA on
    // whichever canvas it lands on. See the status table in the brand guide.
    static let success = adaptive(light: "#0F7A43", dark: "#3FD483")
    static let warning = adaptive(light: "#8A5300", dark: "#F0A93B")
    static let error = adaptive(light: "#B3242E", dark: "#FF7A85")
    static let neutral = adaptive(light: "#5A5970", dark: "#A9A7BC")

    /// Separation is normally a material step or a glow. This hairline is the
    /// fallback for the few places where neither is possible.
    static let hairline = adaptiveColor(
        light: NSColor.black.withAlphaComponent(0.06),
        dark: NSColor.white.withAlphaComponent(0.08)
    )

    private static func adaptive(light: String, dark: String) -> Color {
        adaptiveColor(light: NSColor(Color(hex: light)!), dark: NSColor(Color(hex: dark)!))
    }

    private static func adaptiveColor(light: NSColor, dark: NSColor) -> Color {
        Color(
            nsColor: NSColor(name: nil) { appearance in
                appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
            })
    }
}

enum BrandSpacing {
    static let xs: CGFloat = 6
    static let sm: CGFloat = 10
    static let md: CGFloat = 16
    static let lg: CGFloat = 24
    static let xl: CGFloat = 32
    static let xxl: CGFloat = 44
    static let xxxl: CGFloat = 60
}

/// All rounding is continuous. Nothing interactive is squarer than `sm`.
enum BrandRadius {
    static let sm: CGFloat = 12
    static let md: CGFloat = 18
    static let lg: CGFloat = 26
    static let xl: CGFloat = 34
    static let xxl: CGFloat = 44
}

enum BrandTypography {
    static let heroTitle = Font.system(size: 40, weight: .bold, design: .rounded)
    static let sectionTitle = Font.system(size: 24, weight: .semibold, design: .rounded)
    static let cardTitle = Font.system(size: 18, weight: .semibold, design: .rounded)
    static let body = Font.system(size: 15, weight: .regular, design: .rounded)
    static let caption = Font.system(size: 12, weight: .medium, design: .rounded)
    static let mono = Font.system(size: 12, weight: .regular, design: .monospaced)
}

/// Elevation is a tinted glow, never a hard black drop shadow.
///
/// Applied by `auraCard` and `auraHeroGlow` in `Compatibility.swift`. The tint is
/// the active theme's primary rather than a fixed indigo, so custom themes stay
/// coherent instead of glowing the wrong colour.
enum BrandElevation {
    case low, high

    var radius: CGFloat { self == .low ? 12 : 28 }
    var y: CGFloat { self == .low ? 4 : 10 }

    func color(tint: Color, scheme: ColorScheme) -> Color {
        switch (self, scheme) {
        case (.low, .dark): tint.opacity(0.22)
        case (.low, _): tint.opacity(0.10)
        case (.high, .dark): tint.opacity(0.30)
        case (.high, _): tint.opacity(0.14)
        }
    }
}

/// The Aura halo: a soft gradient ring with a small core, drawn natively so it
/// stays crisp at every size. The glow is part of the mark, not a shadow behind it.
struct BrandMark: View {
    var monochrome = false
    /// Rotates the sweep. Driven by `SweepingBrandMark`; static callers leave it at zero.
    var sweep: Angle = .zero

    @Environment(\.appTheme) private var theme

    // Proportions match brand/aura-symbol.svg on its 64-point canvas.
    private let ringDiameter: CGFloat = 46.0 / 64.0
    private let ringWidth: CGFloat = 5.5 / 64.0
    private let glowWidth: CGFloat = 8.0 / 64.0
    private let glowBlur: CGFloat = 3.4 / 64.0
    private let coreDiameter: CGFloat = 11.0 / 64.0

    var body: some View {
        GeometryReader { proxy in
            let size = min(proxy.size.width, proxy.size.height)
            ZStack {
                if monochrome {
                    ring(size: size, width: ringWidth, shading: AnyShapeStyle(Color.primary))
                    core(size: size, shading: AnyShapeStyle(Color.primary))
                } else {
                    ring(size: size, width: glowWidth, shading: shading)
                        .blur(radius: size * glowBlur)
                        .opacity(0.45)
                    ring(size: size, width: ringWidth, shading: shading)
                    core(size: size, shading: shading)
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityLabel("Aura")
    }

    /// The brand sweep for the default theme; a two-stop sweep in the theme's own
    /// colors otherwise, so custom themes still tint the mark.
    private var shading: AnyShapeStyle {
        if theme.id == AppTheme.defaultID { return AnyShapeStyle(BrandColors.sweep(angle: sweep)) }
        return AnyShapeStyle(
            AngularGradient(
                gradient: Gradient(colors: [theme.secondaryColor, theme.primaryColor, theme.secondaryColor]),
                center: .center,
                angle: sweep
            )
        )
    }

    private func ring(size: CGFloat, width: CGFloat, shading: AnyShapeStyle) -> some View {
        Circle()
            .stroke(shading, lineWidth: size * width)
            .frame(width: size * ringDiameter, height: size * ringDiameter)
    }

    private func core(size: CGFloat, shading: AnyShapeStyle) -> some View {
        Circle()
            .fill(shading)
            .frame(width: size * coreDiameter, height: size * coreDiameter)
    }
}

/// The brand motion signature: the halo's gradient sweeps slowly around the ring
/// while something is playing. Freezes in place — never hides — under Reduce Motion.
struct SweepingBrandMark: View {
    var isPlaying = false
    var monochrome = false
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
            BrandMark(monochrome: monochrome, sweep: sweepAngle(at: context.date))
        }
    }

    private func sweepAngle(at date: Date) -> Angle {
        guard isPlaying, !reduceMotion else { return .zero }
        let phase = date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: Self.period)
        return .degrees(phase / Self.period * 360)
    }
}

/// A template image for macOS status items.
///
/// `MenuBarExtra` labels are hosted by AppKit, so use an image-backed view here
/// instead of `Canvas`. Marking the image as a template lets macOS apply the
/// correct menu-bar tint for the current appearance and selection state.
struct MenuBarBrandMark: View {
    var body: some View {
        Image(nsImage: Self.image)
    }

    private static let statusItemSize = NSSize(width: 18, height: 18)

    static let image: NSImage = {
        guard
            let url = menuBarSymbolURL(),
            let image = NSImage(contentsOf: url)
        else {
            let fallback =
                NSImage(systemSymbolName: "circle.circle", accessibilityDescription: "Aura")
                ?? NSImage(size: statusItemSize)
            fallback.size = statusItemSize
            fallback.isTemplate = true
            return fallback
        }

        // MenuBarExtra uses the NSImage's intrinsic point size when sizing its
        // AppKit status item. The SVG is authored on a 64 × 64 canvas, so a
        // SwiftUI frame alone leaves AppKit with an oversized 64-point label.
        image.size = statusItemSize
        image.isTemplate = true
        return image
    }()

    /// Do not use `Bundle.module` while constructing the menu-bar label. SwiftPM's
    /// generated accessor traps when a damaged or concurrently replaced app bundle
    /// is missing its resource bundle, which would make a cosmetic asset prevent
    /// the entire app from launching. The system symbol remains a safe fallback.
    private static func menuBarSymbolURL() -> URL? {
        let fileName = "aura-symbol-mono.svg"
        if let resourceURL = Bundle.main.resourceURL {
            let packagedBundleURL = resourceURL.appendingPathComponent("Aura_Aura.bundle")
            if let packagedBundle = Bundle(url: packagedBundleURL),
                let url = packagedBundle.url(forResource: "aura-symbol-mono", withExtension: "svg")
            {
                return url
            }
            let directURL = resourceURL.appendingPathComponent(fileName)
            if FileManager.default.fileExists(atPath: directURL.path) { return directURL }
        }
        return nil
    }
}
