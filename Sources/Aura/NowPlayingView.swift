import AuraCore
import SwiftUI

/// The dashboard's home. There is no boxed hero: the whole pane takes its light
/// from the cover, the artwork carries the halo's glow while it plays, and the
/// page reads top to bottom as the product does — what is playing, then where
/// it is going.
struct NowPlayingView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.appTheme) private var theme

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: BrandSpacing.xxl) {
                if model.demoModeEnabled {
                    AuraCallout(
                        symbol: "testtube.2",
                        tint: theme.readablePrimary(for: colorScheme),
                        title: "Demo playback",
                        message: "Sample tracks are running through Aura. Discord and Last.fm publishing are paused."
                    ) {
                        Button("End Demo") { model.setDemoModeEnabled(false) }
                            .auraButton()
                    }
                }
                if model.snapshot.track == nil {
                    emptyStage
                } else {
                    stage
                }
                NowPlayingPipeline()
                RecentActivitySection()
            }
            .frame(maxWidth: DashboardLayout.contentWidth, alignment: .leading)
            .padding(.horizontal, BrandMetrics.screenPadding)
            .padding(.top, BrandSpacing.md)
            .padding(.bottom, BrandMetrics.screenPadding)
            .frame(maxWidth: .infinity)
        }
        .background {
            AmbientArtworkBackdrop(image: model.artworkImage)
                .animation(reduceMotion ? nil : .easeInOut(duration: 0.8), value: currentTrackIdentifier)
        }
    }

    // MARK: Stage

    private var stage: some View {
        let isPlaying = model.snapshot.state == .playing
        return ViewThatFits(in: .horizontal) {
            HStack(alignment: .center, spacing: BrandSpacing.xxl) {
                stageArtwork(size: BrandMetrics.stageArtwork, isPlaying: isPlaying)
                trackDetails
                    .frame(minWidth: 340, maxWidth: 540, alignment: .leading)
            }
            VStack(alignment: .leading, spacing: BrandSpacing.lg) {
                stageArtwork(size: BrandMetrics.stageArtworkCompact, isPlaying: isPlaying)
                trackDetails
            }
        }
        .padding(.vertical, BrandSpacing.lg)
        .padding(.horizontal, BrandSpacing.sm)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.3), value: currentTrackIdentifier)
    }

    private func stageArtwork(size: CGFloat, isPlaying: Bool) -> some View {
        ArtworkAura(cornerRadius: size * ArtworkView.cornerRatio, isPlaying: isPlaying) {
            ArtworkView(
                image: model.artworkImage,
                size: size,
                accessibilityDescription: artworkAccessibilityDescription,
                placeholderText: artworkPlaceholder,
                isPlaying: isPlaying
            )
        }
        .id(currentTrackIdentifier)
        .transition(.opacity.combined(with: .scale(scale: 0.97)))
    }

    private var trackDetails: some View {
        VStack(alignment: .leading, spacing: BrandSpacing.md) {
            HStack(spacing: BrandSpacing.xs) {
                StatusDot(tint: model.snapshot.state == .playing ? BrandColors.blush : BrandColors.neutral)
                Text(eyebrow)
                    .auraEyebrow()
                    .foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .combine)

            VStack(alignment: .leading, spacing: BrandSpacing.xs) {
                Text(model.snapshot.track?.title ?? "")
                    .font(BrandTypography.heroTitle)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
                Text(model.snapshot.track?.artist ?? "")
                    .font(.title3.weight(.medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                if let album = model.snapshot.track?.album, !album.isEmpty {
                    Text(album)
                        .font(.callout)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }

            if let track = model.snapshot.track, track.supportsFiniteProgress {
                PlaybackProgress(snapshot: model.snapshot, duration: track.duration)
                    .padding(.top, BrandSpacing.xs)
            }

            HStack(spacing: BrandSpacing.lg) {
                if model.canControlPlayback {
                    transportControls
                }
                HStack(spacing: BrandSpacing.sm) {
                    if let url = model.snapshot.track?.appleMusicURL {
                        Link(destination: url) {
                            Label("Open in \(model.snapshot.track?.platform.rawValue ?? "Music")", systemImage: "arrow.up.forward.app")
                        }
                        .auraButton()
                    }
                    moreMenu
                }
            }
            .padding(.top, BrandSpacing.xs)
        }
    }

    private var transportControls: some View {
        HStack(spacing: BrandSpacing.md) {
            TransportButton(title: "Previous", symbol: "backward.fill", diameter: 42) {
                model.performPlaybackControl(.previous)
            }
            TransportButton(
                title: model.snapshot.state == .playing ? "Pause" : "Play",
                symbol: model.snapshot.state == .playing ? "pause.fill" : "play.fill",
                diameter: 56,
                prominent: true
            ) {
                model.performPlaybackControl(.toggle)
            }
            .keyboardShortcut(.space, modifiers: [])
            TransportButton(title: "Next", symbol: "forward.fill", diameter: 42) {
                model.performPlaybackControl(.next)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Control \(model.snapshot.track?.platform.rawValue ?? "playback")")
    }

    private var moreMenu: some View {
        Menu {
            if !model.demoModeEnabled {
                Button("Reload Album Artwork", systemImage: "photo.badge.arrow.down") {
                    model.retryCurrentArtwork()
                }
            }
            Button("Discord Settings", systemImage: "bubble.left.and.bubble.right") {
                model.openSettings(.discord)
            }
            Button("Last.fm Settings", systemImage: "dot.radiowaves.left.and.right") {
                model.openSettings(.lastFM)
            }
            Divider()
            Button(model.isPrivate ? "End Private Mode" : "Go Private", systemImage: model.isPrivate ? "eye" : "eye.slash") {
                model.isPrivate ? model.endPrivateMode() : model.setPrivate(until: nil)
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(Color.primary.opacity(0.85))
                .frame(width: 42, height: 42)
                .background(.primary.opacity(0.08), in: .circle)
                .contentShape(.circle)
        }
        .menuStyle(.button)
        .buttonStyle(RoundButtonStyle())
        .menuIndicator(.hidden)
        .fixedSize()
        .help("More actions")
        .accessibilityLabel("More actions")
    }

    private var emptyStage: some View {
        VStack(spacing: BrandSpacing.lg) {
            BrandMark()
                .frame(width: 96, height: 96)
            VStack(spacing: BrandSpacing.sm) {
                Text(model.demoModeEnabled ? "Starting demo playback…" : "Nothing playing yet")
                    .font(BrandTypography.pageTitle)
                Text(
                    model.demoModeEnabled
                        ? "A sample track will appear here in a moment."
                        : "Start a song in a supported music app and Aura will pick it up."
                )
                .font(.title3)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            }
            if !model.demoModeEnabled {
                HStack(spacing: BrandSpacing.xs) {
                    ForEach(PlaybackPlatform.allCases) { platform in
                        Text(platform.rawValue)
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, BrandSpacing.sm)
                            .padding(.vertical, 5)
                            .background(.primary.opacity(0.06), in: .capsule)
                    }
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Supported apps: \(PlaybackPlatform.allCases.map(\.rawValue).joined(separator: ", "))")
                Button("Try Demo Playback", systemImage: "play.fill") {
                    model.setDemoModeEnabled(true)
                }
                .auraButton(prominent: true)
                .controlSize(.large)
                .help("Try Aura without a music app or service account")
            } else {
                ProgressView().controlSize(.small)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, BrandSpacing.xxxl)
        .accessibilityElement(children: .contain)
    }

    // MARK: Copy

    private var eyebrow: String {
        let platform = model.snapshot.track?.platform.rawValue
        switch model.snapshot.state {
        case .playing: return ["Now playing", platform].compactMap { $0 }.joined(separator: " · ")
        case .paused: return ["Paused", platform].compactMap { $0 }.joined(separator: " · ")
        case .stopped: return "Stopped"
        }
    }

    private var artworkAccessibilityDescription: String {
        guard let track = model.snapshot.track else { return "Album artwork unavailable" }
        if model.artworkLoadState == .available(.generatedPlaceholder) {
            return "Designed album placeholder for \(track.title)"
        }
        return model.artworkImage == nil ? "Album artwork unavailable for \(track.title)" : "Album artwork for \(track.title)"
    }

    private var artworkPlaceholder: String? {
        guard let track = model.snapshot.track else { return nil }
        let words = track.album?.isEmpty == false ? track.album!.split(separator: " ") : track.title.split(separator: " ")
        let letters = words.prefix(2).compactMap(\.first)
        return letters.isEmpty ? nil : String(letters).uppercased()
    }

    private var currentTrackIdentifier: String {
        model.snapshot.track?.identity.persistentID ?? "empty"
    }
}

// MARK: - Pipeline

/// Player → Discord → Last.fm, in one row. The three stages the product exists
/// to connect, each with its state in words and a way to fix it in place.
private struct NowPlayingPipeline: View {
    @Environment(AppModel.self) private var model
    @Environment(\.appTheme) private var theme
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        AuraSection(title: "Where it’s going", detail: "From your player to the places you’ve chosen to share.") {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: 0) {
                    sourceStage
                    connector
                    discordStage
                    connector
                    lastFMStage
                }
                .fixedSize(horizontal: false, vertical: true)
                VStack(spacing: BrandMetrics.gridSpacing) {
                    sourceStage
                    discordStage
                    lastFMStage
                }
            }
        }
    }

    private var connector: some View {
        Image(systemName: "chevron.compact.right")
            .font(.title3.weight(.semibold))
            .foregroundStyle(.quaternary)
            .frame(width: 22)
            .frame(maxHeight: .infinity)
            .accessibilityHidden(true)
    }

    private var sourceStage: some View {
        PipelineStage(
            role: "Player",
            name: model.playbackServiceName,
            symbol: "music.note",
            statusTitle: model.musicStatus.presentationLabel,
            statusTint: model.musicStatus.tintColor
        ) {
            Text(model.musicStatus.detailLabel ?? sourceDetail)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: BrandSpacing.xs) {
                Image(systemName: artworkSymbol)
                    .foregroundStyle(artworkTint)
                    .accessibilityHidden(true)
                Text(artworkDetail)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                Spacer(minLength: 0)
                if model.snapshot.track != nil, !model.demoModeEnabled {
                    Button("Reload Artwork", systemImage: "arrow.clockwise") { model.retryCurrentArtwork() }
                        .labelStyle(.iconOnly)
                        .buttonStyle(.borderless)
                        .help("Clear the cached cover and load it again")
                }
            }
            .font(.caption)
            if model.musicStatus == .awaitingPermission {
                Button("Allow Access") { model.openAutomationSettings() }
                    .auraButton(prominent: true)
                    .controlSize(.small)
            }
        }
    }

    private var discordStage: some View {
        PipelineStage(
            role: "Presence",
            name: "Discord",
            symbol: "bubble.left.and.bubble.right.fill",
            statusTitle: model.isPrivate ? "Paused" : model.discordStatus.presentationLabel,
            statusTint: model.isPrivate ? BrandColors.warning : model.discordStatus.tintColor
        ) {
            Text(discordDetail)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if model.isPrivate {
                Button("Resume Sharing") { model.endPrivateMode() }
                    .auraButton()
                    .controlSize(.small)
            } else if !model.preferences.discordEnabled {
                Button("Set Up Discord") { model.openSettings(.discord) }
                    .auraButton()
                    .controlSize(.small)
            } else if let title = discordRecoveryTitle {
                Button(title) { model.refreshDiscord() }
                    .auraButton()
                    .controlSize(.small)
            }
        }
    }

    private var lastFMStage: some View {
        let presentation = model.captureStatus
        let tint = presentation.status.tint(theme, in: colorScheme)
        return PipelineStage(
            role: "Scrobbling",
            name: "Last.fm",
            symbol: "dot.radiowaves.left.and.right",
            statusTitle: presentation.status.title,
            statusTint: tint
        ) {
            VStack(alignment: .leading, spacing: BrandMetrics.titleDetailSpacing) {
                Text(presentation.headline)
                    .font(.callout.weight(.semibold))
                    .lineLimit(2)
                Text(presentation.explanation)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let progress = presentation.progress {
                HStack(spacing: BrandSpacing.sm) {
                    AuraProgressBar(value: progress, live: model.snapshot.state == .playing, height: 4)
                    if case .listening(_, let remaining) = model.scrobblePresentation {
                        Text(remaining.formattedDuration)
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
                .accessibilityElement()
                .accessibilityLabel("Scrobble eligibility")
                .accessibilityValue(progress.formatted(.percent.precision(.fractionLength(0))))
            }
            if let action = presentation.recoveryAction {
                Button(action.buttonTitle) { model.performCaptureRecovery(action) }
                    .auraButton()
                    .controlSize(.small)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(presentation.accessibilitySummary)
    }

    private var sourceDetail: String {
        model.snapshot.track == nil ? "Watching for playback on this Mac" : "Reading playback on this Mac"
    }

    private var discordDetail: String {
        if model.isPrivate { return "Private Mode has cleared your presence." }
        guard model.preferences.discordEnabled else { return "Presence sharing is off." }
        switch model.discordStatus {
        case .connected: return connectionDetail(for: .discord)
        case .offline: return "Discord Desktop is closed. Aura reconnects when it opens."
        case .inactive: return "Ready. Aura shares when music plays."
        case .failed(let message): return message
        default: return connectionDetail(for: .discord)
        }
    }

    private var discordRecoveryTitle: String? {
        switch model.discordStatus {
        case .offline: "Check Again"
        case .failed: "Try Again"
        default: nil
        }
    }

    private var artworkDetail: String {
        switch model.artworkLoadState {
        case .idle: "Artwork appears with the next track"
        case .loading: "Finding the best matching cover…"
        case .available(let source): "Artwork from \(source.label)"
        case .unavailable: "No trustworthy cover found"
        }
    }

    private var artworkSymbol: String {
        switch model.artworkLoadState {
        case .idle: "photo"
        case .loading: "arrow.trianglehead.2.clockwise.rotate.90"
        case .available: "photo.fill"
        case .unavailable: "photo.badge.exclamationmark"
        }
    }

    private var artworkTint: Color {
        switch model.artworkLoadState {
        case .available: BrandColors.success
        case .unavailable: BrandColors.warning
        default: BrandColors.neutral
        }
    }

    private func connectionDetail(for id: IntegrationID) -> String {
        guard let health = model.integrationHealth.first(where: { $0.integration == id }) else {
            return "No successful connection yet"
        }
        if let date = health.lastSuccessfulAt {
            return "Last connected \(date.formatted(.relative(presentation: .named)))"
        }
        return health.summary
    }
}

private struct PipelineStage<Content: View>: View {
    let role: String
    let name: String
    let symbol: String
    let statusTitle: String
    let statusTint: Color
    @ViewBuilder var content: Content
    @Environment(\.appTheme) private var theme
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: BrandMetrics.cardContentSpacing) {
            HStack(alignment: .center, spacing: BrandSpacing.sm) {
                SymbolTile(symbol: symbol, tint: theme.readablePrimary(for: colorScheme), size: BrandMetrics.tileMedium)
                VStack(alignment: .leading, spacing: 1) {
                    Text(role)
                        .auraEyebrow()
                        .foregroundStyle(.tertiary)
                    Text(name)
                        .font(.headline)
                        .lineLimit(1)
                }
                Spacer(minLength: BrandSpacing.xs)
            }
            StatusPill(title: statusTitle, tint: statusTint)
            content
            Spacer(minLength: 0)
        }
        .padding(BrandMetrics.cardPadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .auraSurface(.plain)
        .accessibilityElement(children: .contain)
    }
}

// MARK: - Recent activity

private struct RecentActivitySection: View {
    @Environment(AppModel.self) private var model
    @Environment(\.appTheme) private var theme
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        // Read once: the model derives this list on every access.
        let activity = model.recentCaptureActivity
        AuraSection(title: "Recent activity", detail: "Why each recent play was or wasn’t scrobbled.") {
            RowGroup {
                if activity.isEmpty {
                    Text("Finished and interrupted plays will be explained here.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .padding(.vertical, BrandSpacing.md)
                } else {
                    ForEach(Array(activity.enumerated()), id: \.element.id) { index, entry in
                        if index > 0 { RowDivider(inset: BrandMetrics.tileSmall + BrandSpacing.sm) }
                        HStack(spacing: BrandSpacing.sm) {
                            SymbolTile(
                                symbol: entry.status.symbol,
                                tint: entry.status.tint(theme, in: colorScheme),
                                size: BrandMetrics.tileSmall
                            )
                            VStack(alignment: .leading, spacing: 1) {
                                Text(entry.headline)
                                    .font(.callout.weight(.semibold))
                                    .lineLimit(1)
                                Text(entry.explanation)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                            }
                            Spacer(minLength: BrandSpacing.sm)
                            if let timestamp = entry.timestamp {
                                Text(timestamp, style: .relative)
                                    .font(.caption.monospacedDigit())
                                    .foregroundStyle(.tertiary)
                            }
                        }
                        .padding(.vertical, BrandSpacing.sm)
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel(entry.accessibilitySummary)
                    }
                }
            }
        }
    }
}

// Titles, symbols, and tone come from `AuraCore` so the Mac and iPhone
// apps describe the same situation identically. Only the palette is local.
extension CaptureStatusPresentation.Status {
    /// Status tone is semantic and fixed, with one exception: "active" is the app
    /// speaking about itself, so it follows the chosen theme instead of pinning
    /// the default indigo onto every other palette.
    func tint(_ theme: AppTheme, in scheme: ColorScheme) -> Color {
        switch tone {
        case .positive: BrandColors.success
        case .active: theme.readablePrimary(for: scheme)
        case .paused: BrandColors.warning
        case .neutral: BrandColors.neutral
        case .critical: BrandColors.error
        }
    }
}
