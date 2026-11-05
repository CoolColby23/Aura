import AppKit
import SwiftUI

// The components every dashboard page, the menu-bar panel, and Settings are
// assembled from. A page should read as a composition of these rather than a
// set of one-off stacks: when two screens need the same thing, they reach for
// the same component and inherit the same measurements.

// MARK: - Page structure

/// A scrolling dashboard page: a large title, then titled sections, centered in
/// the shared content measure so switching pages never shifts the column.
struct AuraPage<Accessory: View, Content: View>: View {
    let title: String
    var subtitle: String?
    @ViewBuilder var accessory: Accessory
    @ViewBuilder var content: Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: BrandMetrics.sectionSpacing) {
                PageHeader(title: title, subtitle: subtitle) { accessory }
                content
            }
            .frame(maxWidth: DashboardLayout.contentWidth, alignment: .leading)
            .padding(.horizontal, BrandMetrics.screenPadding)
            .padding(.top, BrandSpacing.md)
            .padding(.bottom, BrandMetrics.screenPadding)
            .frame(maxWidth: .infinity)
        }
    }
}

extension AuraPage where Accessory == EmptyView {
    init(title: String, subtitle: String? = nil, @ViewBuilder content: () -> Content) {
        self.init(title: title, subtitle: subtitle, accessory: { EmptyView() }, content: content)
    }
}

struct PageHeader<Accessory: View>: View {
    let title: String
    var subtitle: String?
    @ViewBuilder var accessory: Accessory

    var body: some View {
        HStack(alignment: .bottom, spacing: BrandSpacing.md) {
            VStack(alignment: .leading, spacing: BrandSpacing.xs) {
                Text(title)
                    .font(BrandTypography.pageTitle)
                    .accessibilityAddTraits(.isHeader)
                if let subtitle {
                    Text(subtitle)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: BrandSpacing.md)
            accessory
        }
    }
}

/// A titled block within a page. The title is small and quiet; the content
/// carries the weight.
struct AuraSection<Accessory: View, Content: View>: View {
    let title: String
    var detail: String?
    @ViewBuilder var accessory: Accessory
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: BrandMetrics.cardContentSpacing) {
            HStack(alignment: .firstTextBaseline, spacing: BrandSpacing.sm) {
                VStack(alignment: .leading, spacing: BrandMetrics.titleDetailSpacing) {
                    Text(title)
                        .font(BrandTypography.groupTitle)
                        .accessibilityAddTraits(.isHeader)
                    if let detail {
                        Text(detail)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: BrandSpacing.sm)
                accessory
            }
            content
        }
    }
}

extension AuraSection where Accessory == EmptyView {
    init(title: String, detail: String? = nil, @ViewBuilder content: () -> Content) {
        self.init(title: title, detail: detail, accessory: { EmptyView() }, content: content)
    }
}

/// Rows stacked on one surface, separated by inset dividers the caller places
/// with `RowDivider`.
struct RowGroup<Content: View>: View {
    var style: AuraSurfaceStyle = .plain
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            content
        }
        .padding(.horizontal, BrandMetrics.cardPadding)
        .padding(.vertical, BrandSpacing.xs)
        .frame(maxWidth: .infinity, alignment: .leading)
        .auraSurface(style)
    }
}

struct RowDivider: View {
    var inset: CGFloat = BrandMetrics.rowDividerInset

    var body: some View {
        Rectangle()
            .fill(BrandColors.hairline)
            .frame(height: 1)
            .padding(.leading, inset)
    }
}

// MARK: - Status vocabulary

struct StatusDot: View {
    let tint: Color
    var size: CGFloat = BrandMetrics.statusDot

    var body: some View {
        Circle()
            .fill(tint)
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

/// The tinted capsule that labels a state. Always carries text, so state is
/// never encoded in color alone.
struct StatusPill: View {
    let title: String
    var symbol: String?
    let tint: Color

    var body: some View {
        Group {
            if let symbol {
                Label(title, systemImage: symbol)
            } else {
                Text(title)
            }
        }
        .font(.caption2.weight(.semibold))
        .lineLimit(1)
        .foregroundStyle(tint)
        .padding(.horizontal, BrandMetrics.capsuleHorizontal)
        .padding(.vertical, BrandMetrics.capsuleVertical)
        .background(tint.opacity(0.12), in: .capsule)
    }
}

/// The small tinted square that fronts a row or card. Rounded to a fixed ratio
/// of its edge so every size reads as the same shape.
struct SymbolTile: View {
    let symbol: String
    let tint: Color
    var size: CGFloat = BrandMetrics.tileMedium
    var filled = false

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: size * 0.42, weight: .semibold))
            .foregroundStyle(filled ? Color.white : tint)
            .frame(width: size, height: size)
            .background(
                filled ? AnyShapeStyle(tint.gradient) : AnyShapeStyle(tint.opacity(0.13)),
                in: .rect(cornerRadius: BrandRadius.tile(size), style: .continuous)
            )
            .accessibilityHidden(true)
    }
}

struct KeyCap: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.caption.monospaced().weight(.semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(.quaternary.opacity(0.7), in: .rect(cornerRadius: BrandRadius.xxs, style: .continuous))
    }
}

/// A banner that sits inline on the canvas: demo playback, recovery, a queue
/// that needs attention. Tinted by tone, never boxed with a border.
struct AuraCallout<Actions: View>: View {
    let symbol: String
    let tint: Color
    let title: String
    var message: String?
    @ViewBuilder var actions: Actions

    var body: some View {
        HStack(alignment: .center, spacing: BrandMetrics.cardContentSpacing) {
            SymbolTile(symbol: symbol, tint: tint, size: BrandMetrics.tileMedium)
            VStack(alignment: .leading, spacing: BrandMetrics.titleDetailSpacing) {
                Text(title)
                    .font(.callout.weight(.semibold))
                if let message {
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: BrandSpacing.sm)
            actions
        }
        .padding(.horizontal, BrandMetrics.cardPadding)
        .padding(.vertical, BrandMetrics.cardPaddingCompact)
        .background(tint.opacity(0.09), in: .rect(cornerRadius: BrandRadius.md, style: .continuous))
        .accessibilityElement(children: .contain)
    }
}

/// A centered empty state with the halo as its only bright object.
struct AuraEmptyState<Actions: View>: View {
    var symbol: String?
    let title: String
    let message: String
    @ViewBuilder var actions: Actions
    @Environment(\.appTheme) private var theme

    var body: some View {
        VStack(spacing: BrandSpacing.md) {
            Group {
                if let symbol {
                    Image(systemName: symbol)
                        .font(.system(size: 30, weight: .semibold))
                        .foregroundStyle(theme.primaryColor)
                        .frame(width: 64, height: 64)
                        .background(theme.primaryColor.opacity(0.10), in: .circle)
                } else {
                    BrandMark().frame(width: 64, height: 64)
                }
            }
            .accessibilityHidden(true)
            VStack(spacing: BrandSpacing.xs) {
                Text(title)
                    .font(BrandTypography.cardTitle)
                Text(message)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: 380)
            actions
        }
        .padding(BrandSpacing.xl)
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .contain)
    }
}

extension AuraEmptyState where Actions == EmptyView {
    init(symbol: String? = nil, title: String, message: String) {
        self.init(symbol: symbol, title: title, message: message, actions: { EmptyView() })
    }
}

// MARK: - Live playback

extension AppTheme {
    /// The linear form of the live-state gradient, for progress that is filling
    /// while something plays. The default theme uses the brand sweep; other
    /// themes use their own two stops.
    var liveGradient: LinearGradient {
        if id == AppTheme.defaultID {
            return LinearGradient(
                stops: [
                    .init(color: BrandColors.peach, location: 0),
                    .init(color: BrandColors.blush, location: 0.34),
                    .init(color: BrandColors.lilac, location: 0.70),
                    .init(color: BrandColors.indigo, location: 1),
                ],
                startPoint: .leading,
                endPoint: .trailing
            )
        }
        return LinearGradient(colors: [secondaryColor, primaryColor], startPoint: .leading, endPoint: .trailing)
    }
}

/// A slim capsule progress bar. Live progress takes the live gradient; anything
/// else — a ranking, a share of a total — takes the flat theme color.
struct AuraProgressBar: View {
    let value: Double
    var total: Double = 1
    var live = false
    var height: CGFloat = 5
    var tint: Color?
    @Environment(\.appTheme) private var theme

    var body: some View {
        GeometryReader { proxy in
            let fraction = total > 0 ? min(max(value / total, 0), 1) : 0
            ZStack(alignment: .leading) {
                Capsule().fill(.primary.opacity(0.09))
                Capsule()
                    .fill(live ? AnyShapeStyle(theme.liveGradient) : AnyShapeStyle(tint ?? theme.primaryColor))
                    .frame(width: max(fraction > 0 ? height : 0, proxy.size.width * fraction))
            }
        }
        .frame(height: height)
        .accessibilityHidden(true)
    }
}

/// The aura around the playing artwork: the halo's sweep, blurred into light
/// behind the cover. It turns with the halo while something plays, dims when
/// paused, and freezes rather than disappearing under Reduce Motion.
struct ArtworkAura<Content: View>: View {
    let cornerRadius: CGFloat
    let isPlaying: Bool
    @ViewBuilder var content: Content
    @Environment(\.appTheme) private var theme
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        content
            .background {
                BrandSweep(isPlaying: isPlaying) { angle in
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(theme.haloShading(angle: angle))
                        .scaleEffect(1.04)
                        .blur(radius: 34)
                        .opacity(isPlaying ? (colorScheme == .dark ? 0.62 : 0.48) : 0.18)
                }
                .animation(.easeInOut(duration: 0.6), value: isPlaying)
                .accessibilityHidden(true)
            }
    }
}

/// Album artwork as ambient light for a whole pane. The cover is blurred far
/// past recognition and a material sits between it and any text.
struct AmbientArtworkBackdrop: View {
    let image: NSImage?
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.appTheme) private var theme

    var body: some View {
        ZStack {
            theme.canvas(for: colorScheme)
            if let image {
                Color.clear.overlay {
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFill()
                        .blur(radius: 90)
                        .saturation(1.3)
                        .opacity(colorScheme == .dark ? 0.55 : 0.45)
                }
                .clipped()
                .transition(.opacity)
            } else {
                RadialGradient(
                    colors: [theme.secondaryColor.opacity(0.16), .clear],
                    center: .topLeading,
                    startRadius: 0,
                    endRadius: 700
                )
            }
            Rectangle().fill(.regularMaterial).opacity(colorScheme == .dark ? 0.55 : 0.5)
            LinearGradient(
                colors: [.clear, theme.canvas(for: colorScheme).opacity(0.85)],
                startPoint: .center,
                endPoint: .bottom
            )
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }
}

extension ServiceStatus {
    var symbol: String {
        switch self {
        case .connected: "checkmark.circle.fill"
        case .connecting: "arrow.trianglehead.2.clockwise"
        case .awaitingPermission: "lock.fill"
        case .authorizationExpired: "key.fill"
        case .failed: "exclamationmark.triangle.fill"
        case .offline: "moon.zzz.fill"
        case .disabled: "minus.circle.fill"
        case .inactive: "pause.circle.fill"
        }
    }
}

// MARK: - Round controls

/// A round transport or module button that shrinks slightly while pressed.
struct RoundButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.92 : 1)
            .opacity(configuration.isPressed ? 0.85 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

/// Previous, play/pause, and next. The primary button is filled with the theme;
/// the others are quiet discs so play/pause is always the obvious target.
struct TransportButton: View {
    let title: String
    let symbol: String
    var diameter: CGFloat = 40
    var prominent = false
    let action: () -> Void
    @Environment(\.appTheme) private var theme

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: diameter * (prominent ? 0.36 : 0.34), weight: .bold))
                .foregroundStyle(prominent ? theme.onPrimaryColor : Color.primary.opacity(0.85))
                .frame(width: diameter, height: diameter)
                .background {
                    if prominent {
                        Circle()
                            .fill(theme.primaryColor.gradient)
                            .shadow(color: theme.primaryColor.opacity(0.35), radius: 10, y: 4)
                    } else {
                        Circle().fill(.primary.opacity(0.08))
                    }
                }
                .contentShape(.circle)
        }
        .buttonStyle(RoundButtonStyle())
        .help(title)
        .accessibilityLabel(title)
    }
}

/// A round Control Center toggle: a quiet disc when off, filled when on.
struct ModuleToggleCircle: View {
    let symbol: String
    let isOn: Bool
    var tint: Color?
    var diameter: CGFloat = 32
    let action: () -> Void
    @Environment(\.appTheme) private var theme

    var body: some View {
        let fill = tint ?? theme.primaryColor
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: diameter * 0.4, weight: .semibold))
                .foregroundStyle(isOn ? Color.white : Color.primary.opacity(0.75))
                .frame(width: diameter, height: diameter)
                .background(isOn ? AnyShapeStyle(fill.gradient) : AnyShapeStyle(Color.primary.opacity(0.10)), in: .circle)
                .contentShape(.circle)
        }
        .buttonStyle(RoundButtonStyle())
        .animation(.easeOut(duration: 0.15), value: isOn)
    }
}
