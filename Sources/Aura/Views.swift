import AppKit
import SwiftData
import SwiftUI

struct ArtworkView: View {
    let data: Data?
    let image: NSImage?
    let size: CGFloat
    var accessibilityDescription: String? = nil
    var placeholderText: String? = nil
    /// Sweeps the placeholder halo while playback is live. History rows leave this
    /// false so past plays stay still.
    var isPlaying: Bool = false
    @Environment(\.appTheme) private var theme

    init(
        data: Data?, size: CGFloat, accessibilityDescription: String? = nil, placeholderText: String? = nil,
        isPlaying: Bool = false
    ) {
        self.data = data
        image = nil
        self.size = size
        self.accessibilityDescription = accessibilityDescription
        self.placeholderText = placeholderText
        self.isPlaying = isPlaying
    }

    init(
        image: NSImage?, size: CGFloat, accessibilityDescription: String? = nil, placeholderText: String? = nil,
        isPlaying: Bool = false
    ) {
        data = nil
        self.image = image
        self.size = size
        self.accessibilityDescription = accessibilityDescription
        self.placeholderText = placeholderText
        self.isPlaying = isPlaying
    }

    /// Artwork corners scale with the cover so a 40-point thumbnail and the
    /// stage artwork read as the same shape.
    static let cornerRatio: CGFloat = 0.12

    var body: some View {
        Group {
            if let image = image ?? data.flatMap(NSImage.init(data:)) {
                Image(nsImage: image).resizable().scaledToFill()
            } else {
                ZStack {
                    LinearGradient(
                        colors: [theme.darkBackground, theme.darkBackground.mixed(with: .black, amount: 0.35), theme.primaryColor.opacity(0.55)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    if let placeholderText {
                        Text(placeholderText)
                            .font(.system(size: size * 0.25, weight: .bold, design: .rounded))
                            .foregroundStyle(.white.opacity(0.88))
                    } else {
                        SweepingBrandMark(isPlaying: isPlaying)
                            .padding(size * 0.2)
                    }
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(.rect(cornerRadius: size * Self.cornerRatio, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: size * Self.cornerRatio, style: .continuous)
                .strokeBorder(BrandColors.hairline, lineWidth: 1)
        }
        .accessibilityLabel(accessibilityDescription ?? (image == nil && data == nil ? "Album artwork unavailable" : "Album artwork"))
    }
}

enum DashboardLayout {
    static let minimumWidth: CGFloat = 640
    static let minimumHeight: CGFloat = 520

    /// The measure every detail screen centers its content in. Now Playing,
    /// Status & Support, and Listening History previously chose 1040, 980, and
    /// 1100, so the content column jumped when the sidebar selection changed.
    static let contentWidth: CGFloat = 1040
}

struct PersistenceRecoveryBanner: View {
    @Environment(AppModel.self) private var model
    let message: String
    @State private var confirmingEmptySession = false

    var body: some View {
        HStack(spacing: BrandMetrics.cardContentSpacing) {
            SymbolTile(symbol: "externaldrive.badge.exclamationmark", tint: BrandColors.warning)
            VStack(alignment: .leading, spacing: BrandMetrics.titleDetailSpacing) {
                Text("Local data needs recovery").font(.callout.weight(.semibold))
                Text(message).font(.caption).foregroundStyle(.secondary).lineLimit(3)
                if !model.persistenceRecoveryStatus.isEmpty {
                    Text(model.persistenceRecoveryStatus).font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
            if model.usingTemporaryStore {
                Button("Restore Database Backup") { model.restoreLatestDatabaseBackup() }
                Button("Start Fresh…") { confirmingEmptySession = true }
                Button("Restart Aura") { model.restartApplication() }
            } else {
                Button("Open Data Settings") { model.openSettings(.data) }
                Button("Dismiss") { model.persistenceIssue = nil }
            }
        }
        .controlSize(.small)
        .padding(.horizontal, BrandSpacing.md)
        .padding(.vertical, BrandMetrics.cardPaddingCompact)
        .background(BrandColors.warning.opacity(0.10))
        .background(.bar)
        .accessibilityElement(children: .contain)
        .confirmationDialog("Start with a new local database?", isPresented: $confirmingEmptySession, titleVisibility: .visible) {
            Button("Preserve Failed Store and Start Fresh", role: .destructive) { model.prepareFreshDatabase() }
        } message: {
            Text("Aura will move the failed database into a recovery folder and create a new store after restart. It will not delete the failed data.")
        }
    }
}

extension TimeInterval {
    var formattedDuration: String {
        let total = max(0, Int(self.rounded()))
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}

#Preview("Playing") {
    let store = try! PersistenceStore(inMemory: true)
    let model = AppModel(store: store)
    let track = TrackMetadata(
        identity: .init(persistentID: "preview"), title: "Midnight Signal", artist: "Aura",
        album: "Afterglow", duration: 246, source: .appleMusicCatalog,
        appleMusicURL: URL(string: "https://music.apple.com"), artworkReference: nil
    )
    model.snapshot = .init(track: track, state: .playing, position: 92, observedAt: .now, confidence: .high)
    model.activeSession = .init(
        id: UUID(), track: track, startedAt: .now.addingTimeInterval(-92), accumulatedPlayTime: 82, lastPosition: 92, eligibility: .listening, outcome: .active)
    model.musicStatus = .connected
    model.discordStatus = .connected
    model.lastFMStatus = .connected
    return NowPlayingView().environment(model).modelContainer(store.container).frame(width: 900, height: 650)
}

#Preview("Permission Required") {
    let store = try! PersistenceStore(inMemory: true)
    let model = AppModel(store: store)
    model.musicStatus = .awaitingPermission
    model.discordStatus = .offline
    model.lastFMStatus = .authorizationExpired
    return NowPlayingView().environment(model).modelContainer(store.container).frame(width: 900, height: 650)
}
