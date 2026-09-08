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

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 5) {
                WidgetBrandMark(monochrome: isTinted)
                    .frame(width: 15, height: 15)
                Text("Aura")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .accessibilityElement()
            .accessibilityLabel("Aura")
            Spacer()
            if entry.snapshot?.isPrivate == true {
                Label("Private Mode", systemImage: "eye.slash.fill").font(.headline)
                Text("Listening details are hidden").font(.caption).foregroundStyle(.secondary)
            } else if let snapshot = entry.snapshot {
                Text(snapshot.title).font(.headline).lineLimit(2)
                Text(snapshot.artist).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                Text(snapshot.platform).font(.caption2).foregroundStyle(.tertiary)
                if snapshot.duration > 0 {
                    // The gradient is reserved for the halo and for live playback
                    // state; a progress bar that is filling is exactly the latter.
                    ProgressView(value: currentPosition(snapshot), total: snapshot.duration)
                        .tint(isTinted ? nil : AnyShapeStyle(WidgetBrand.sweep))
                }
            } else {
                Text("Open Aura").font(.headline)
                Text("Launch the app to update this widget.").font(.caption).foregroundStyle(.secondary)
            }
        }
        .containerBackground(for: .widget) {
            ZStack {
                Rectangle().fill(.background)
                if !isTinted {
                    // Elevation in this system is a tinted glow, so the widget is
                    // lit from its corner rather than given a border or a fill.
                    RadialGradient(
                        colors: [WidgetBrand.lilac.opacity(0.16), .clear],
                        center: .topTrailing,
                        startRadius: 0,
                        endRadius: 190
                    )
                }
            }
        }
        .widgetURL(URL(string: "aura://now-playing"))
    }

    private var isTinted: Bool { renderingMode != .fullColor }

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
