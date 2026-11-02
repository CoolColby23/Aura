import Foundation
import SwiftUI
import WidgetKit

private struct WidgetSnapshot: Codable {
    let title: String
    let artist: String
    let platform: String
    let state: String
    let position: TimeInterval
    let duration: TimeInterval
    let observedAt: Date
    let isPrivate: Bool
}

private struct AuraEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot?
}

private struct AuraProvider: TimelineProvider {
    func placeholder(in context: Context) -> AuraEntry {
        AuraEntry(date: .now, snapshot: sample)
    }

    func getSnapshot(in context: Context, completion: @escaping (AuraEntry) -> Void) {
        completion(AuraEntry(date: .now, snapshot: load() ?? sample))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<AuraEntry>) -> Void) {
        let now = Date.now
        completion(
            Timeline(
                entries: [AuraEntry(date: now, snapshot: load())],
                policy: .after(now.addingTimeInterval(60))
            ))
    }

    private func load() -> WidgetSnapshot? {
        guard let defaults = UserDefaults(suiteName: "group.fm.aura.Aura"),
            let data = defaults.data(forKey: "widgetSnapshot")
        else { return nil }
        return try? JSONDecoder().decode(WidgetSnapshot.self, from: data)
    }

    private var sample: WidgetSnapshot {
        WidgetSnapshot(
            title: "Midnight Signal", artist: "Aura", platform: "Apple Music",
            state: "playing", position: 42, duration: 180, observedAt: .now, isPrivate: false
        )
    }
}

/// The widget cannot import the app module, so the brand values it needs are
/// restated here. They are canonical in `brand/design-tokens.md`; change them
/// there first, then in `Sources/Aura/Brand.swift`, `iOS/CompanionTheme.swift`,
/// and here.
private enum WidgetBrand {
    static let peach = Color(hex: 0xFF_C4_9B)
    static let blush = Color(hex: 0xFF_9A_A8)
    static let lilac = Color(hex: 0xA7_8B_FA)
    static let indigo = Color(hex: 0x5B_5B_F5)
    /// Status warning, dark form. Private Mode is the only status the widget shows.
    static let warning = Color(hex: 0xF0_A9_3B)

    /// The Aura sweep at the positions the marks use: peach in, indigo out.
    static let sweep = LinearGradient(
        stops: [
            .init(color: peach, location: 0.00),
            .init(color: blush, location: 0.34),
            .init(color: lilac, location: 0.70),
            .init(color: indigo, location: 1.00),
        ],
        startPoint: .leading,
        endPoint: .trailing
    )
}

private extension Color {
    init(hex: UInt32) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }
}

/// The Aura halo, matching `BrandMark` on macOS and `CompanionBrandMark` on iOS:
/// a gradient ring with a small core and a blurred copy behind it for the glow.
/// Proportions come from `brand/aura-symbol.svg` on its 64-point canvas.
private struct WidgetBrandMark: View {
    /// Accented and vibrant widget rendering modes flatten every color to the
    /// desktop tint, where a gradient turns to mud. The mono halo — flat ring plus
    /// flat core, no glow — is the brand's own answer for exactly that case.
    var monochrome = false

    var body: some View {
        GeometryReader { proxy in
            let size = min(proxy.size.width, proxy.size.height)
            let shading: AnyShapeStyle =
                monochrome ? AnyShapeStyle(.secondary) : AnyShapeStyle(WidgetBrand.sweep)
            ZStack {
                if !monochrome {
                    Circle()
                        .stroke(shading, lineWidth: size * (8.0 / 64.0))
                        .frame(width: size * (46.0 / 64.0), height: size * (46.0 / 64.0))
                        .blur(radius: size * (3.4 / 64.0))
                        .opacity(0.45)
                }
                Circle()
                    .stroke(shading, lineWidth: size * (5.5 / 64.0))
                    .frame(width: size * (46.0 / 64.0), height: size * (46.0 / 64.0))
                Circle()
                    .fill(shading)
                    .frame(width: size * (11.0 / 64.0), height: size * (11.0 / 64.0))
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .aspectRatio(1, contentMode: .fit)
    }
}

private struct AuraWidgetView: View {
    let entry: AuraEntry
    @Environment(\.widgetRenderingMode) private var renderingMode
    @Environment(\.widgetFamily) private var family

    var body: some View {
        Group {
            if entry.snapshot?.isPrivate == true {
                privateState
            } else if let snapshot = entry.snapshot {
                if family == .systemMedium {
                    mediumPlaying(snapshot)
                } else {
                    smallPlaying(snapshot)
                }
            } else {
                emptyState
            }
        }
        .containerBackground(for: .widget) {
            ZStack {
                Rectangle().fill(.background)
                if !isTinted {
                    // Elevation in this system is a tinted glow, so the widget is
                    // lit from its corner rather than given a border or a fill.
                    RadialGradient(
                        colors: [WidgetBrand.lilac.opacity(isLive ? 0.22 : 0.12), .clear],
                        center: .topLeading,
                        startRadius: 0,
                        endRadius: family == .systemMedium ? 260 : 190
                    )
                }
            }
        }
        .widgetURL(URL(string: "aura://now-playing"))
    }

    // MARK: Playing

    private func smallPlaying(_ snapshot: WidgetSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                halo(size: 34)
                Spacer()
                liveBadge(snapshot)
            }
            Spacer(minLength: 6)
            Text(snapshot.title)
                .font(.system(.headline, design: .rounded).weight(.semibold))
                .lineLimit(2)
            Text(snapshot.artist)
                .font(.system(.caption, design: .rounded))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            if snapshot.duration > 0 {
                progressBar(snapshot)
                    .padding(.top, 8)
            }
        }
    }

    private func mediumPlaying(_ snapshot: WidgetSnapshot) -> some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(isTinted ? AnyShapeStyle(.quaternary) : AnyShapeStyle(WidgetBrand.indigo.opacity(0.10)))
                halo(size: 64)
            }
            .frame(width: 104, height: 104)
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 5) {
                    if snapshot.state == "playing" && !isTinted {
                        Circle().fill(WidgetBrand.blush).frame(width: 6, height: 6)
                    }
                    Text(eyebrow(snapshot))
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                        .tracking(1.05)
                        .textCase(.uppercase)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 4)
                Text(snapshot.title)
                    .font(.system(.title3, design: .rounded).weight(.semibold))
                    .lineLimit(2)
                Text(snapshot.artist)
                    .font(.system(.callout, design: .rounded))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer(minLength: 6)
                if snapshot.duration > 0 {
                    progressBar(snapshot)
                    HStack {
                        Text(formatted(currentPosition(snapshot)))
                        Spacer()
                        Text("−" + formatted(max(0, snapshot.duration - currentPosition(snapshot))))
                    }
                    .font(.system(size: 10, weight: .medium, design: .rounded).monospacedDigit())
                    .foregroundStyle(.tertiary)
                    .padding(.top, 4)
                }
            }
        }
    }

    // MARK: Other states

    private var privateState: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .top) {
                Image(systemName: "eye.slash.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(isTinted ? AnyShapeStyle(.primary) : AnyShapeStyle(Color.white))
                    .frame(width: 34, height: 34)
                    .background(isTinted ? AnyShapeStyle(.quaternary) : AnyShapeStyle(WidgetBrand.warning), in: .circle)
                Spacer()
                halo(size: 18)
            }
            Spacer(minLength: 6)
            Text("You’re private")
                .font(.system(.headline, design: .rounded).weight(.semibold))
            Text(family == .systemMedium
                ? "Discord presence is cleared and Last.fm updates are paused."
                : "Listening details are hidden.")
                .font(.system(.caption, design: .rounded))
                .foregroundStyle(.secondary)
                .lineLimit(3)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 4) {
            halo(size: 34)
            Spacer(minLength: 6)
            Text("Nothing playing yet")
                .font(.system(.headline, design: .rounded).weight(.semibold))
            Text("Start a song and Aura will pick it up.")
                .font(.system(.caption, design: .rounded))
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    // MARK: Pieces

    private func halo(size: CGFloat) -> some View {
        WidgetBrandMark(monochrome: isTinted)
            .frame(width: size, height: size)
            .accessibilityElement()
            .accessibilityLabel("Aura")
    }

    @ViewBuilder
    private func liveBadge(_ snapshot: WidgetSnapshot) -> some View {
        Text(snapshot.state == "playing" ? "Live" : "Paused")
            .font(.system(size: 10, weight: .semibold, design: .rounded))
            .foregroundStyle(snapshot.state == "playing" && !isTinted ? WidgetBrand.blush : Color.secondary)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(.quaternary.opacity(0.6), in: .capsule)
    }

    /// The gradient is reserved for the halo and for live playback state; a
    /// progress bar that is filling is exactly the latter.
    private func progressBar(_ snapshot: WidgetSnapshot) -> some View {
        GeometryReader { proxy in
            let fraction = snapshot.duration > 0 ? currentPosition(snapshot) / snapshot.duration : 0
            ZStack(alignment: .leading) {
                Capsule().fill(.quaternary)
                Capsule()
                    .fill(isTinted ? AnyShapeStyle(.primary) : AnyShapeStyle(WidgetBrand.sweep))
                    .frame(width: max(4, proxy.size.width * min(max(fraction, 0), 1)))
            }
        }
        .frame(height: 4)
        .accessibilityElement()
        .accessibilityLabel("Playback progress")
        .accessibilityValue("\(formatted(currentPosition(snapshot))) of \(formatted(snapshot.duration))")
    }

    private func eyebrow(_ snapshot: WidgetSnapshot) -> String {
        (snapshot.state == "playing" ? "Now playing · " : "Paused · ") + snapshot.platform
    }

    private var isLive: Bool { entry.snapshot?.state == "playing" && entry.snapshot?.isPrivate == false }

    private var isTinted: Bool { renderingMode != .fullColor }

    private func formatted(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds.rounded()))
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    private func currentPosition(_ snapshot: WidgetSnapshot) -> TimeInterval {
        let elapsed = snapshot.state == "playing" ? max(0, entry.date.timeIntervalSince(snapshot.observedAt)) : 0
        return min(snapshot.duration, max(0, snapshot.position + elapsed))
    }
}

@main
struct AuraWidget: Widget {
    let kind = "AuraNowPlaying"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: AuraProvider()) { entry in
            AuraWidgetView(entry: entry)
        }
        .configurationDisplayName("Aura Now Playing")
        .description("See the current track and playback progress at a glance.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}
