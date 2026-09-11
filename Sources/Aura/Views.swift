import AppKit
import SwiftData
import SwiftUI

struct DashboardView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.appTheme) private var theme
    var body: some View {
        @Bindable var model = model
        NavigationSplitView {
            VStack(spacing: 0) {
                SidebarHeader()
                    .padding(.horizontal, BrandSpacing.md)
                    .padding(.top, BrandSpacing.md)
                    .padding(.bottom, BrandSpacing.sm)
                List(selection: $model.selectedSection) {
                    Section("Listen") {
                        ForEach(visibleSections([.nowPlaying, .history])) { section in
                            SidebarNavigationRow(section: section, selected: model.selectedSection == section)
                                .tag(section)
                                .contextMenu { sidebarContextMenu(for: section) }
                        }
                    }
                    Section("Manage") {
                        ForEach(visibleSections([.queue, .diagnostics, .settings])) { section in
                            SidebarNavigationRow(section: section, selected: model.selectedSection == section)
                                .tag(section)
                                .contextMenu { sidebarContextMenu(for: section) }
                        }
                    }
                }
                .listStyle(.sidebar)
                .tint(theme.primaryColor)
                .scrollContentBackground(.hidden)
                .accessibilityIdentifier("dashboard.navigation")
                .safeAreaInset(edge: .bottom) {
                    VStack(spacing: BrandSpacing.sm) {
                        sidebarCustomization
                        SidebarPrivacyControl()
                    }
                    .padding(.horizontal, BrandSpacing.md)
                    .padding(.bottom, BrandSpacing.sm)
                }
            }
            .navigationSplitViewColumnWidth(min: 220, ideal: 250, max: 310)
        } detail: {
            Group {
                switch model.selectedSection {
                case .nowPlaying: NowPlayingView()
                case .history: ListeningHistoryView()
                case .queue: QueueView()
                case .diagnostics: DiagnosticsView()
                case .settings: SettingsView()
                }
            }.environment(model)
        }
        .task { model.start() }
        .sheet(isPresented: $model.onboardingPresented) { OnboardingView().environment(model) }
        .sheet(isPresented: $model.commandPalettePresented) {
            CommandPaletteView().environment(model)
        }
        .safeAreaInset(edge: .top) {
            if let issue = model.persistenceIssue {
                PersistenceRecoveryBanner(message: issue)
            }
        }
        .auraPanelBackground()
        .frame(minWidth: DashboardLayout.minimumWidth, minHeight: DashboardLayout.minimumHeight)
    }

    private func visibleSections(_ sections: [DashboardSection]) -> [DashboardSection] {
        sections.filter(model.preferences.isDashboardSectionVisible)
    }

    @ViewBuilder
    private func sidebarContextMenu(for section: DashboardSection) -> some View {
        if section.canBeHidden {
            Button("Hide from Sidebar", systemImage: "eye.slash") {
                model.preferences.toggleDashboardSection(section)
                if model.selectedSection == section { model.navigate(to: .nowPlaying) }
            }
        }
    }

    private var sidebarCustomization: some View {
        HStack {
            Button("Quick Open", systemImage: "command") {
                model.commandPalettePresented = true
            }
            .buttonStyle(.plain)
            .help("Open commands (Command-K)")
            Spacer()
            Menu("Customize", systemImage: "slider.horizontal.3") {
                ForEach(DashboardSection.allCases.filter(\.canBeHidden)) { section in
                    Button {
                        model.preferences.toggleDashboardSection(section)
                        if model.selectedSection == section,
                            !model.preferences.isDashboardSectionVisible(section)
                        {
                            model.navigate(to: .nowPlaying)
                        }
                    } label: {
                        Label(
                            section.title,
                            systemImage: model.preferences.isDashboardSectionVisible(section)
                                ? "checkmark" : section.symbol
                        )
                    }
                }
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 4)
    }
}

private struct SidebarNavigationRow: View {
    let section: DashboardSection
    let selected: Bool
    @Environment(\.appTheme) private var theme
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.controlActiveState) private var controlActiveState

    var body: some View {
        Label(section.title, systemImage: section.symbol)
            .font(.callout.weight(.semibold))
            // macOS paints its own opaque selection over a selectable List row.
            // DashboardView tints that selection with the active theme, so the
            // label must use the matching on-primary color rather than placing
            // the primary color on top of itself. When the window is inactive
            // that selection fades to a translucent wash, so the label falls
            // back to the readable accent instead of white-on-pale.
            .foregroundStyle(selectedLabelStyle)
            .padding(.vertical, 4)
            .listRowBackground(
                RoundedRectangle(cornerRadius: BrandRadius.md, style: .continuous)
                    .fill(selected ? theme.primaryColor.opacity(0.16) : Color.clear)
                    .padding(.vertical, 2)
            )
            .accessibilityIdentifier("dashboard.section.\(section.id.rawValue)")
    }

    private var selectedLabelStyle: Color {
        guard selected else { return .primary }
        return controlActiveState == .key ? theme.onPrimaryColor : theme.readablePrimary(for: colorScheme)
    }
}

struct NowPlayingView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.appTheme) private var theme
    var body: some View {
        ScrollView {
            VStack(spacing: BrandMetrics.screenPadding) {
                if model.demoModeEnabled {
                    HStack(spacing: BrandMetrics.gridSpacing) {
                        Label("Demo playback is active — Discord and Last.fm publishing are paused", systemImage: "testtube.2")
                            .font(.callout.weight(.semibold))
                            .foregroundStyle(theme.readablePrimary(for: colorScheme))
                        Spacer()
                        Button("End Demo") { model.setDemoModeEnabled(false) }
                    }
                    .padding(BrandMetrics.cardPadding)
                    .auraCard(elevated: true)
                    .frame(maxWidth: DashboardLayout.contentWidth)
                    .accessibilityElement(children: .contain)
                }
                heroSection
                    .frame(maxWidth: DashboardLayout.contentWidth)
                VStack(alignment: .leading, spacing: BrandMetrics.cardContentSpacing) {
                    VStack(alignment: .leading, spacing: BrandMetrics.titleDetailSpacing) {
                        Text("At a glance").font(BrandTypography.sectionTitle)
                        Text("See where playback and artwork came from, plus what Aura shared.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                    NowPlayingOverviewView()
                }
                .frame(maxWidth: DashboardLayout.contentWidth)
            }
            .padding(BrandMetrics.screenPadding)
            .frame(maxWidth: .infinity)
        }
        .navigationTitle("Now Playing")
    }

    @ViewBuilder
    private var heroSection: some View {
        if model.snapshot.track == nil {
            emptyHeroSection
        } else {
            populatedHeroSection
        }
    }

    private var populatedHeroSection: some View {
        let currentTrackID = model.snapshot.track?.identity.persistentID ?? "empty"
        let isPlaying = model.snapshot.state == .playing && !reduceMotion
        return ZStack {
            heroBackground
            VStack(alignment: .leading, spacing: BrandSpacing.xl) {
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .center, spacing: BrandSpacing.xl) {
                        heroArtwork(size: 300, isPlaying: isPlaying)
                        nowPlayingDetails
                            .frame(minWidth: 380, maxWidth: 560, alignment: .leading)
                    }
                    VStack(spacing: BrandSpacing.lg) {
                        heroArtwork(size: 220, isPlaying: isPlaying)
                        nowPlayingDetails
                            .frame(maxWidth: 620, alignment: .leading)
                    }
                }
            }
            .padding(BrandSpacing.xl)
        }
        .frame(maxWidth: .infinity)
        .clipShape(.rect(cornerRadius: BrandRadius.xxl, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: BrandRadius.xxl, style: .continuous)
                .strokeBorder(theme.secondaryColor.opacity(0.16), lineWidth: 1)
        }
        .auraCard(elevated: true)
        .auraHeroGlow(active: model.snapshot.state == .playing)
        .tint(theme.readablePrimary(for: .dark))
        .environment(\.colorScheme, .dark)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.28), value: currentTrackID)
    }

    private var emptyHeroSection: some View {
        ZStack {
            heroBackground
            ViewThatFits(in: .horizontal) {
                HStack(spacing: BrandSpacing.lg) {
                    BrandMark()
                        .frame(width: 92, height: 92)
                        .padding(BrandSpacing.lg)
                        .background(.ultraThinMaterial, in: .rect(cornerRadius: BrandRadius.lg, style: .continuous))
                    nowPlayingDetails
                        .frame(maxWidth: 620, alignment: .leading)
                }
                VStack(alignment: .leading, spacing: BrandSpacing.md) {
                    BrandMark().frame(width: 72, height: 72)
                    nowPlayingDetails
                }
            }
            .padding(BrandSpacing.xl)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .clipShape(.rect(cornerRadius: BrandRadius.xxl, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: BrandRadius.xxl, style: .continuous)
                .strokeBorder(theme.secondaryColor.opacity(0.16), lineWidth: 1)
        }
        .auraCard(elevated: true)
        .tint(theme.readablePrimary(for: .dark))
        .environment(\.colorScheme, .dark)
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private var nowPlayingDetails: some View {
        VStack(alignment: .leading, spacing: BrandSpacing.md) {
            Label(playbackLabel, systemImage: model.snapshot.state == .playing ? "dot.radiowaves.left.and.right" : "music.note")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .labelStyle(.titleAndIcon)
                .textCase(.uppercase)
            Text(model.snapshot.track?.title ?? "Nothing Playing")
                .font(BrandTypography.heroTitle)
                .lineLimit(2)
            Text(metadataLabel)
                .font(.title3.weight(.medium))
                .foregroundStyle(.secondary)
                .lineLimit(2)
            if let track = model.snapshot.track {
                if track.supportsFiniteProgress {
                    PlaybackProgress(snapshot: model.snapshot, duration: track.duration)
                }
                if model.canControlPlayback {
                    playbackControls
                }
                HStack(spacing: BrandSpacing.sm) {
                    if let url = track.appleMusicURL {
                        Link("Open in \(track.platform.rawValue)", destination: url)
                            .auraButton(prominent: true)
                    }
                    Menu {
                        if !model.demoModeEnabled {
                            Button("Reload Album Artwork", systemImage: "photo.badge.arrow.down") {
                                model.retryCurrentArtwork()
                            }
                        }
                        Button("Open Connection Settings", systemImage: "antenna.radiowaves.left.and.right") {
                            model.openSettings(.integrations)
                        }
                        Divider()
                        Button(model.isPrivate ? "End Private Mode" : "Go Private", systemImage: model.isPrivate ? "eye" : "eye.slash") {
                            model.isPrivate ? model.endPrivateMode() : model.setPrivate(until: nil)
                        }
                    } label: {
                        Label("More actions", systemImage: "ellipsis")
                    }
                    // Same chrome as the transport buttons: the borderless
                    // style drew bare accent dots that read as a stray glyph
                    // when demo playback has no store link beside them.
                    .labelStyle(.iconOnly)
                    .menuStyle(.button)
                    .auraButton()
                    .menuIndicator(.hidden)
                    .fixedSize()
                    .help("More actions")
                }
                ScrobbleProgress(state: model.scrobblePresentation)
            } else {
                VStack(alignment: .leading, spacing: BrandSpacing.sm) {
                    if model.demoModeEnabled {
                        Text("Starting safe demo playback…")
                    } else {
                        Text("Play something in a supported music app and Aura will pick it up automatically.")
                        Text("Apple Music · Spotify · YouTube Music · TIDAL")
                            .font(.callout.weight(.medium))
                            .foregroundStyle(.secondary)
                        Button("Start Demo Playback", systemImage: "play.fill") {
                            model.setDemoModeEnabled(true)
                        }
                        .auraButton(prominent: true)
                        .help("Try Aura without a music app or service account")
                    }
                }
                .padding(.top, 4)
            }
        }
    }

    private var playbackControls: some View {
        HStack(spacing: BrandSpacing.sm) {
            Button("Previous", systemImage: "backward.fill") { model.performPlaybackControl(.previous) }
                .labelStyle(.iconOnly)
                .auraButton()
            Button(
                model.snapshot.state == .playing ? "Pause" : "Play",
                systemImage: model.snapshot.state == .playing ? "pause.fill" : "play.fill"
            ) { model.performPlaybackControl(.toggle) }
            .labelStyle(.iconOnly)
            .auraButton(prominent: true)
            .keyboardShortcut(.space, modifiers: [])
            Button("Next", systemImage: "forward.fill") { model.performPlaybackControl(.next) }
                .labelStyle(.iconOnly)
                .auraButton()
            Text("Control \(model.snapshot.track?.platform.rawValue ?? "playback")")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .contain)
    }

    private var playbackLabel: String {
        switch model.snapshot.state {
        case .playing: "Now playing";
        case .paused: "Paused";
        case .stopped: "Aura is ready"
        }
    }

    private var metadataLabel: String {
        guard let track = model.snapshot.track else { return "Waiting for playback" }
        return "\(track.artist)\(track.album.map { " • \($0)" } ?? "")"
    }

    private var artworkAccessibilityDescription: String {
        guard let track = model.snapshot.track else { return "Album artwork unavailable" }
        if model.artworkLoadState == .available(.generatedPlaceholder) {
            return "Designed album placeholder for \(track.title)"
        }
        return model.artworkImage == nil ? "Album artwork unavailable for \(track.title)" : "Album artwork for \(track.title)"
    }

    private func heroArtwork(size: CGFloat, isPlaying: Bool) -> some View {
        ZStack {
            ArtworkView(
                image: model.artworkImage,
                size: size,
                accessibilityDescription: artworkAccessibilityDescription,
                placeholderText: artworkPlaceholder,
                isPlaying: isPlaying
            )
            .auraHeroGlow(active: isPlaying)
            .overlay(alignment: .bottomTrailing) {
                Label(
                    model.snapshot.state == .playing ? "Playing" : "Paused",
                    systemImage: model.snapshot.state == .playing ? "waveform" : "pause.fill"
                )
                .font(.caption.weight(.bold))
                .padding(.horizontal, BrandMetrics.capsuleHorizontal)
                .padding(.vertical, BrandMetrics.capsuleVertical)
                .background(.ultraThinMaterial, in: .capsule)
                .padding(size * 0.045)
            }
        }
        .id(currentTrackIdentifier)
        .transition(.opacity.combined(with: .scale(scale: 0.98)))
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

    private var heroBackground: some View {
        ZStack {
            if let image = model.artworkImage {
                // Overlay the cover on a flexible base so it fills whatever
                // the hero content measures. As a direct ZStack child a
                // square cover scaled to fill would set the card's height to
                // its own width and stretch the hero down the whole window.
                Color.clear.overlay {
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFill()
                        .blur(radius: 68)
                        .scaleEffect(1.18)
                        .opacity(0.34)
                }
            } else {
                LinearGradient(
                    colors: [theme.secondaryColor.opacity(0.18), theme.primaryColor.opacity(0.12), Color.clear],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            }
            Rectangle().fill(theme.darkBackground.opacity(0.52))
            RadialGradient(
                colors: [theme.secondaryColor.opacity(0.20), .clear],
                center: .topLeading,
                startRadius: 10,
                endRadius: 560
            )
            RadialGradient(
                colors: [theme.primaryColor.opacity(0.18), .clear],
                center: .bottomTrailing,
                startRadius: 10,
                endRadius: 520
            )
        }
        .clipped()
    }

    private var discordRecoveryTitle: String? {
        guard model.preferences.discordEnabled else { return nil }
        return switch model.discordStatus {
        case .offline: "Open Discord"
        case .failed: "Try Again"
        default: nil
        }
    }

    private var lastFMRecoveryTitle: String? {
        guard model.preferences.lastFMEnabled else { return nil }
        return model.lastFMStatus.isConnected || model.lastFMStatus == .connecting ? nil : IntegrationID.lastFM.recoveryTitle
    }
}

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
        .clipShape(.rect(cornerRadius: size * 0.12, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: size * 0.12, style: .continuous).strokeBorder(.white.opacity(0.14), lineWidth: 1) }
        .shadow(color: .black.opacity(0.24), radius: size * 0.10, y: size * 0.05)
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

struct ScrobbleProgress: View {
    let state: ScrobblePresentationState?
    @Environment(\.appTheme) private var theme
    var body: some View {
        if let state {
            VStack(alignment: .leading, spacing: BrandSpacing.xs) {
                HStack {
                    Label(state.label, systemImage: symbol(for: state)).font(.subheadline.weight(.semibold))
                    Spacer()
                    if case .listening(_, let remaining) = state { Text("\(remaining.formattedDuration) to go").font(.caption).foregroundStyle(.secondary) }
                }
                switch state {
                case .listening(let progress, _): ProgressView(value: progress).tint(theme.accentGradient)
                case .ineligible(let reason): Text(reason).font(.caption).foregroundStyle(.secondary)
                default: EmptyView()
                }
            }
            .padding(BrandMetrics.cardPaddingCompact)
            .background(theme.primaryColor.opacity(0.08), in: .rect(cornerRadius: BrandRadius.md, style: .continuous))
        }
    }

    private func symbol(for state: ScrobblePresentationState) -> String {
        switch state {
        case .ineligible: "nosign";
        case .listening: "waveform";
        case .ready: "checkmark.circle";
        case .queued: "tray";
        case .submitted: "checkmark.circle.fill"
        }
    }
}

struct SidebarHeader: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        HStack(spacing: BrandMetrics.cardPaddingCompact) {
            SweepingBrandMark(isPlaying: model.snapshot.state == .playing)
                .frame(width: 30, height: 30)
                .padding(BrandSpacing.xs)
                .background(.ultraThinMaterial, in: .circle)
            VStack(alignment: .leading, spacing: BrandMetrics.titleDetailSpacing) {
                Text("Aura")
                    .font(BrandTypography.cardTitle)
                HStack(spacing: BrandSpacing.xs) {
                    Circle()
                        .fill(headerStatusColor)
                        .frame(width: BrandMetrics.statusDot, height: BrandMetrics.statusDot)
                    Text(headerDetail)
                        .lineLimit(1)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Aura, \(headerDetail)")
    }

    private var headerDetail: String {
        if model.isPrivate { return "Private Mode active" }
        if model.snapshot.state == .playing, let platform = model.snapshot.track?.platform {
            return "Listening on \(platform.rawValue)"
        }
        return "Watching for music"
    }

    private var headerStatusColor: Color {
        if model.isPrivate { return BrandColors.warning }
        return model.snapshot.state == .playing ? BrandColors.success : BrandColors.neutral
    }
}

struct SidebarPrivacyControl: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: BrandSpacing.sm) {
            Label(model.isPrivate ? "Private Mode is on" : "Go Private", systemImage: model.isPrivate ? "eye.slash.fill" : "eye.slash")
                .font(.callout.weight(.semibold))
            Text(model.isPrivate ? privateDetail : "Pause Discord sharing and Last.fm scrobbling.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            PrivacyControls()
        }
        .padding(BrandMetrics.cardPaddingCompact)
        .frame(maxWidth: .infinity, alignment: .leading)
        .auraCard(elevated: true)
    }

    private var privateDetail: String {
        if let until = model.privateUntil { return "Sharing is paused until \(until.formatted(date: .omitted, time: .shortened))." }
        return "Sharing and scrobbling are paused until you resume them."
    }
}

struct PrivacyControls: View {
    @Environment(AppModel.self) private var model
    var body: some View {
        HStack {
            if model.isPrivate {
                VStack(alignment: .leading, spacing: 4) {
                    Button("End Private Mode", systemImage: "eye") { model.endPrivateMode() }.auraButton(prominent: true)
                    if let until = model.privateUntil {
                        Text("Private until \(until, style: .time)").font(.caption).foregroundStyle(.secondary)
                    }
                }
            } else {
                Menu("Go Private", systemImage: "eye.slash") {
                    Button("For 15 Minutes") { model.setPrivate(until: .now.addingTimeInterval(900)) }
                    Button("For 1 Hour") { model.setPrivate(until: .now.addingTimeInterval(3600)) }
                    Button("Until Resumed") { model.setPrivate(until: nil) }
                }.auraButton()
            }
        }
        .fixedSize(horizontal: true, vertical: false)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(model.isPrivate ? "Private Mode controls" : "Privacy controls")
    }
}

enum QueueFilter: String, CaseIterable, Identifiable {
    case all = "All"
    case waiting = "Waiting"
    case blocked = "Needs Attention"

    var id: String { rawValue }

    func includes(_ record: ScrobbleRecord) -> Bool {
        switch self {
        case .all: record.state != .submitted
        case .waiting: record.state == .pending || record.state == .retrying
        case .blocked: record.state == .permanentlyFailed
        }
    }
}

struct QueueView: View {
    @Environment(AppModel.self) private var model
    @Query(sort: \ScrobbleRecord.startedAt, order: .reverse) private var records: [ScrobbleRecord]
    @State private var pendingRemoval: QueueRemoval?
    @State private var correction: QueueCorrection?
    @State private var filter: QueueFilter = .all
    @State private var searchText = ""
    @State private var confirmingRetryAll = false
    @State private var confirmingRemoveBlocked = false
    var body: some View {
        VStack(spacing: 0) {
            if let commonError {
                QueueRecoveryBanner(
                    count: queuedRecords.count,
                    message: commonError,
                    action: { model.openSettings(.integrations) }
                )
                Divider()
            }
            List {
                if !visibleRecords.isEmpty {
                    QueueSummaryHeader(
                        records: queuedRecords,
                        blockedCount: blockedCount,
                        nextAttemptAt: nextAttemptAt,
                        showBlocked: blockedCount > 0 && filter != .blocked
                    ) {
                        filter = .blocked
                    }
                    .listRowSeparator(.hidden)
                }
                ForEach(visibleRecords) { record in
                    QueueRow(record: record, showsInlineError: record.lastError != commonError) {
                        queueActions(for: record)
                    }
                    .listRowSeparator(.visible)
                    .contextMenu { queueActions(for: record) }
                }
            }
            .listStyle(.inset)
            .scrollContentBackground(.hidden)
            .accessibilityIdentifier("queue.list")
            // Scoped to the list so a recovery banner above it stays readable
            // while the current filter or search matches nothing.
            .overlay { emptyState }
        }
        .navigationTitle("Pending Plays")
        .searchable(text: $searchText, prompt: "Search title, artist, or album")
        .toolbar {
            ToolbarItemGroup {
                Picker("Show", selection: $filter) {
                    ForEach(QueueFilter.allCases) { option in
                        Text(option.rawValue).tag(option)
                    }
                }
                .pickerStyle(.segmented)
                .frame(minWidth: 220, idealWidth: 280, maxWidth: 320)
                .disabled(queuedRecords.isEmpty)
                Menu("More", systemImage: "ellipsis.circle") {
                    Button("Retry All Now", systemImage: "arrow.clockwise") { confirmingRetryAll = true }
                        .disabled(queuedRecords.isEmpty)
                    Divider()
                    Button("Remove All That Need Attention…", systemImage: "trash", role: .destructive) {
                        confirmingRemoveBlocked = true
                    }
                    .disabled(blockedCount == 0)
                }
            }
        }
        .confirmationDialog(
            "Retry every pending play now?",
            isPresented: $confirmingRetryAll,
            titleVisibility: .visible
        ) {
            Button("Retry \(queuedRecords.count) \(queuedRecords.count == 1 ? "Play" : "Plays")") {
                model.retryAllScrobbles()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This clears each play's backoff and error, including plays that previously stopped retrying.")
        }
        .confirmationDialog(
            "Remove every play that needs attention?",
            isPresented: $confirmingRemoveBlocked,
            titleVisibility: .visible
        ) {
            Button("Remove \(blockedCount) \(blockedCount == 1 ? "Play" : "Plays")", role: .destructive) {
                model.removeBlockedScrobbles()
                if filter == .blocked { filter = .all }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Aura stops trying to scrobble them. Plays that are still retrying are kept.")
        }
        .confirmationDialog(
            "Remove this pending play?",
            isPresented: Binding(
                get: { pendingRemoval != nil },
                set: { if !$0 { pendingRemoval = nil } }
            ),
            titleVisibility: .visible,
            presenting: pendingRemoval
        ) { removal in
            Button("Remove \(removal.title)", role: .destructive) {
                model.removeScrobble(id: removal.id)
                pendingRemoval = nil
            }
            Button("Cancel", role: .cancel) { pendingRemoval = nil }
        } message: { removal in
            Text("This stops Aura from retrying “\(removal.title)” with Last.fm.")
        }
        .sheet(item: $correction) { draft in
            QueueCorrectionView(draft: draft) { updated in
                if model.correctScrobble(
                    id: updated.id,
                    title: updated.title,
                    artist: updated.artist,
                    album: updated.album
                ) {
                    correction = nil
                }
            }
        }
    }

    private var queuedRecords: [ScrobbleRecord] { records.filter { $0.state != .submitted } }

    @ViewBuilder
    private var emptyState: some View {
        if queuedRecords.isEmpty {
            ContentUnavailableView {
                Label("Everything Is Synced", systemImage: "checkmark.circle")
            } description: {
                Text("If Last.fm is unavailable, finished plays wait here and retry automatically.")
            }
        } else if visibleRecords.isEmpty {
            ContentUnavailableView {
                Label("No Matching Plays", systemImage: "line.3.horizontal.decrease.circle")
            } description: {
                Text(
                    searchText.isEmpty
                        ? "None of the \(queuedRecords.count) pending plays are in “\(filter.rawValue)”."
                        : "No pending plays match “\(searchText)”."
                )
            } actions: {
                Button("Show All Pending Plays") {
                    filter = .all
                    searchText = ""
                }
            }
        }
    }

    private var visibleRecords: [ScrobbleRecord] {
        let matchingFilter = records.filter(filter.includes)
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return matchingFilter }
        return matchingFilter.filter { record in
            [record.title, record.artist, record.album ?? ""].contains {
                $0.localizedCaseInsensitiveContains(query)
            }
        }
    }

    private var blockedCount: Int {
        queuedRecords.count { $0.state == .permanentlyFailed }
    }

    /// The soonest automatic retry, so the summary can say when the queue moves
    /// on its own rather than implying the person has to do something.
    private var nextAttemptAt: Date? {
        queuedRecords
            .filter { $0.state == .pending || $0.state == .retrying }
            .map(\.nextAttemptAt)
            .min()
    }

    @ViewBuilder
    private func queueActions(for record: ScrobbleRecord) -> some View {
        if record.state == .permanentlyFailed {
            Button("Edit and Retry…", systemImage: "pencil") { requestCorrection(of: record) }
            Button("Retry Without Changes", systemImage: "arrow.clockwise") { model.retryScrobble(id: record.id) }
        }
        Button("Remove…", systemImage: "trash", role: .destructive) { requestRemoval(of: record) }
    }

    private var commonError: String? {
        let errors = queuedRecords.compactMap(\.lastError)
        guard let first = errors.first, errors.count == queuedRecords.count, errors.allSatisfy({ $0 == first }) else { return nil }
        return first
    }

    private func requestRemoval(of record: ScrobbleRecord) {
        pendingRemoval = QueueRemoval(id: record.id, title: record.title)
    }

    private func requestCorrection(of record: ScrobbleRecord) {
        correction = QueueCorrection(
            id: record.id,
            title: record.title,
            artist: record.artist,
            album: record.album ?? ""
        )
    }
}

private struct QueueRemoval: Identifiable {
    let id: UUID
    let title: String
}

private struct QueueSummaryHeader: View {
    let records: [ScrobbleRecord]
    let blockedCount: Int
    let nextAttemptAt: Date?
    let showBlocked: Bool
    let revealBlocked: () -> Void

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: BrandMetrics.cardContentSpacing) {
            VStack(alignment: .leading, spacing: BrandMetrics.titleDetailSpacing) {
                Text("\(records.count) \(records.count == 1 ? "play is" : "plays are") waiting for Last.fm")
                    .font(BrandTypography.cardTitle)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .accessibilityElement(children: .combine)
            Spacer(minLength: 0)
            if showBlocked {
                Button("Show \(blockedCount)", action: revealBlocked)
                    .buttonStyle(.borderless)
                    .accessibilityLabel("Show the \(blockedCount) plays that need attention")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, BrandSpacing.xs)
    }

    private var detail: String {
        guard blockedCount == 0 else {
            return "\(blockedCount) need\(blockedCount == 1 ? "s" : "") a correction before "
                + "\(blockedCount == 1 ? "it" : "they") can be submitted."
        }
        guard let nextAttemptAt, nextAttemptAt > .now else {
            return "Aura keeps retrying these in the background."
        }
        let time = nextAttemptAt.formatted(date: .omitted, time: .shortened)
        return "Aura retries in the background. Next attempt around \(time)."
    }
}

private struct QueueRow<Actions: View>: View {
    let record: ScrobbleRecord
    let showsInlineError: Bool
    @ViewBuilder let actions: () -> Actions
    @Environment(\.appTheme) private var theme

    var body: some View {
        HStack(spacing: BrandMetrics.cardContentSpacing) {
            Image(systemName: symbol)
                .font(.callout.weight(.semibold))
                .foregroundStyle(tint)
                .frame(width: BrandMetrics.tileMedium, height: BrandMetrics.tileMedium)
                .background(tint.opacity(0.12), in: .rect(cornerRadius: BrandRadius.tile(BrandMetrics.tileMedium), style: .continuous))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: BrandMetrics.titleDetailSpacing) {
                Text(record.title)
                    .font(.headline)
                    .lineLimit(1)
                Text(record.album.map { "\(record.artist) • \($0)" } ?? record.artist)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                if showsInlineError, let error = record.lastError {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(BrandColors.error)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: BrandMetrics.cardContentSpacing)
            VStack(alignment: .trailing, spacing: BrandSpacing.xs) {
                Text(record.stateRaw.queueDisplayName)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(tint)
                    .padding(.horizontal, BrandMetrics.capsuleHorizontal)
                    .padding(.vertical, BrandMetrics.capsuleVertical)
                    .background(tint.opacity(0.11), in: .capsule)
                Text(timingDetail)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            .frame(width: BrandMetrics.rowTrailingColumn, alignment: .trailing)
            Menu("Actions", systemImage: "ellipsis.circle", content: actions)
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .labelStyle(.iconOnly)
                .fixedSize()
                .accessibilityLabel("Actions for \(record.title)")
        }
        .padding(.vertical, BrandSpacing.sm)
        .contentShape(.rect)
    }

    private var timingDetail: String {
        // Key on the scheduled attempt, not the state. A retryable failure leaves
        // the record `.pending` with a future `nextAttemptAt`; `.retrying` only
        // marks a submission in flight, so keying on it hid the next attempt for
        // exactly the backed-off rows the summary header counts.
        if record.state != .permanentlyFailed, record.nextAttemptAt > .now {
            return "Retry \(record.nextAttemptAt.formatted(date: .omitted, time: .shortened))"
        }
        return record.startedAt.formatted(.dateTime.month(.abbreviated).day().hour().minute())
    }

    private var symbol: String {
        switch record.state {
        case .pending: "clock"
        case .retrying: "arrow.clockwise"
        case .permanentlyFailed: "exclamationmark.triangle.fill"
        case .submitted: "checkmark.circle.fill"
        }
    }

    private var tint: Color {
        switch record.state {
        case .pending: theme.primaryColor
        case .retrying: BrandColors.warning
        case .permanentlyFailed: BrandColors.error
        case .submitted: BrandColors.success
        }
    }
}

private struct QueueRecoveryBanner: View {
    let count: Int
    let message: String
    let action: () -> Void

    var body: some View {
        HStack(spacing: BrandMetrics.gridSpacing) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(BrandColors.warning)
                .font(.title2)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: BrandMetrics.titleDetailSpacing) {
                Text("\(count) \(count == 1 ? "play needs" : "plays need") attention")
                    .font(.headline)
                Text(message).font(.callout).foregroundStyle(.secondary)
            }
            Spacer()
            Button("Review Last.fm Settings", action: action)
        }
        .padding(.horizontal, BrandSpacing.md)
        .padding(.vertical, BrandMetrics.cardPaddingCompact)
        .background(BrandColors.warning.opacity(0.08))
        .accessibilityElement(children: .contain)
    }
}

struct DiagnosticsView: View {
    @Environment(AppModel.self) private var model
    @Query(sort: \DiagnosticRecord.timestamp, order: .reverse) private var records: [DiagnosticRecord]
    @Query(sort: \IntegrationHealthEvent.timestamp, order: .reverse) private var healthEvents: [IntegrationHealthEvent]
    @State private var showsTechnicalDetails = false
    @State private var artworkCacheSummary = "Loading…"

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: BrandMetrics.screenPadding) {
                VStack(alignment: .leading, spacing: BrandMetrics.titleDetailSpacing) {
                    Text("Connections at a glance")
                        .font(BrandTypography.sectionTitle)
                    Text("See what Aura can detect and share. If something needs attention, you can fix it here.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }

                // Three columns across the full content width, matching the
                // Now Playing status tiles; narrower panes wrap to two, then one.
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 300), spacing: BrandMetrics.gridSpacing, alignment: .top)],
                    alignment: .leading,
                    spacing: BrandMetrics.gridSpacing
                ) {
                    SupportStatusCard(
                        title: model.playbackServiceName,
                        detail: "Music detection",
                        symbol: "music.note",
                        status: model.musicStatus,
                        actionTitle: model.musicStatus == .awaitingPermission ? "Allow Access" : nil,
                        action: model.openAutomationSettings
                    )
                    SupportStatusCard(
                        title: "Discord",
                        detail: "Activity sharing",
                        symbol: "bubble.left.and.bubble.right",
                        status: model.discordStatus,
                        actionTitle: discordActionTitle,
                        action: model.refreshDiscord
                    )
                    SupportStatusCard(
                        title: "Last.fm",
                        detail: "Listening history sync",
                        symbol: "dot.radiowaves.left.and.right",
                        status: model.lastFMStatus,
                        actionTitle: lastFMActionTitle,
                        action: { model.openSettings(.integrations) }
                    )
                }

                VStack(alignment: .leading, spacing: BrandMetrics.cardContentSpacing) {
                    Label("Need help?", systemImage: "lifepreserver")
                        .font(.headline)
                    Text("Copy a privacy-safe report to include when asking for support. It leaves out credentials, usernames, and listening details.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    Button("Copy Support Report", systemImage: "doc.on.doc") {
                        model.copyDiagnosticReport()
                    }
                    .auraButton(prominent: true)
                    if !model.diagnosticCopyStatus.isEmpty {
                        Text(model.diagnosticCopyStatus)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(BrandMetrics.cardPadding)
                .auraCard(elevated: true)

                DisclosureGroup(isExpanded: $showsTechnicalDetails) {
                    VStack(alignment: .leading, spacing: BrandSpacing.md) {
                        technicalSystemDetails
                        technicalPollingDetails
                        technicalExportDetails
                        technicalLogDetails
                        technicalHealthDetails
                    }
                    .padding(.top, BrandSpacing.md)
                } label: {
                    VStack(alignment: .leading, spacing: BrandMetrics.titleDetailSpacing) {
                        Text("Technical details")
                            .font(.headline)
                        Text("Performance measurements, diagnostic logs, and connection history")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.leading, BrandSpacing.xs)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(.rect)
                }
                .padding(BrandMetrics.cardPadding)
                .auraCard()
            }
            .frame(maxWidth: DashboardLayout.contentWidth, alignment: .leading)
            .padding(BrandMetrics.screenPadding)
            .frame(maxWidth: .infinity)
        }
        .navigationTitle("Status & Support")
        .task {
            let metrics = await model.artworkCacheMetrics()
            artworkCacheSummary = "\(metrics.memoryEntries) in memory · \(metrics.diskEntries) on disk"
        }
    }

    private var discordActionTitle: String? {
        guard model.preferences.discordEnabled, !model.discordStatus.isConnected, model.discordStatus != .connecting else { return nil }
        return "Try Again"
    }

    private var lastFMActionTitle: String? {
        switch model.lastFMStatus {
        case .authorizationExpired, .failed: "Open Settings"
        default: nil
        }
    }

    private var technicalSystemDetails: some View {
        VStack(alignment: .leading, spacing: BrandSpacing.sm) {
            Text("App & System").font(.subheadline.weight(.semibold))
            LabeledContent("macOS", value: ProcessInfo.processInfo.operatingSystemVersionString)
            LabeledContent("Aura", value: "\(ReleaseConfiguration.version) (\(ReleaseConfiguration.build))")
            LabeledContent("Artwork cache", value: artworkCacheSummary)
            if model.snapshot.track != nil, model.artworkImage == nil {
                Button("Retry Current Artwork", systemImage: "arrow.clockwise") {
                    model.retryCurrentArtwork()
                }
            }
        }
    }

    private var technicalPollingDetails: some View {
        VStack(alignment: .leading, spacing: BrandSpacing.sm) {
            Text("Playback Check Performance").font(.subheadline.weight(.semibold))
            LabeledContent("Latest check", value: model.playbackPollMetrics.totalDuration.formatted(.number.precision(.fractionLength(1...1))) + " s")
            ForEach(PlaybackProviderID.allCases) { provider in
                if let duration = model.playbackPollMetrics.providerDurations[provider] {
                    LabeledContent(provider.displayName, value: "\(Int((duration * 1_000).rounded())) ms")
                }
            }
        }
    }

    private var technicalExportDetails: some View {
        VStack(alignment: .leading, spacing: BrandSpacing.sm) {
            Text("Verification Snapshot").font(.subheadline.weight(.semibold))
            HStack {
                Button("Copy Snapshot", systemImage: "doc.on.doc", action: model.copyVerificationReport)
                Button("Save Snapshot…", systemImage: "square.and.arrow.down", action: model.saveVerificationReport)
            }
            Text(
                model.verificationExportStatus.isEmpty
                    ? "Exports app and connection health without track metadata, usernames, credentials, or file paths." : model.verificationExportStatus
            )
            .font(.caption).foregroundStyle(.secondary)
        }
    }

    private var technicalLogDetails: some View {
        VStack(alignment: .leading, spacing: BrandSpacing.sm) {
            Text("Recent Diagnostic Messages").font(.subheadline.weight(.semibold))
            if records.isEmpty {
                Text("No diagnostic messages recorded.").foregroundStyle(.secondary)
            } else {
                ForEach(records.prefix(12)) { record in
                    Text("[\(record.category)] \(record.message)").font(.caption.monospaced())
                }
            }
        }
    }

    private var technicalHealthDetails: some View {
        VStack(alignment: .leading, spacing: BrandSpacing.sm) {
            Text("Recent Connection Changes").font(.subheadline.weight(.semibold))
            if healthEvents.isEmpty {
                Text("No connection changes recorded.").foregroundStyle(.secondary)
            } else {
                ForEach(healthEvents.prefix(12)) { event in
                    HStack {
                        Text(IntegrationID(rawValue: event.integrationRaw)?.displayName ?? "Integration")
                        Spacer()
                        Text(IntegrationState(rawValue: event.stateRaw)?.rawValue.capitalized ?? event.stateRaw.capitalized)
                        Text(event.timestamp, style: .relative).foregroundStyle(.secondary)
                    }.font(.caption)
                }
            }
        }
    }
}

private struct SupportStatusCard: View {
    let title: String
    let detail: String
    let symbol: String
    let status: ServiceStatus
    let actionTitle: String?
    let action: () -> Void
    @Environment(\.appTheme) private var theme
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: BrandMetrics.cardContentSpacing) {
            HStack {
                Image(systemName: symbol)
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(theme.readablePrimary(for: colorScheme))
                    .frame(width: BrandMetrics.tileLarge, height: BrandMetrics.tileLarge)
                    .background(theme.subtleAccent(for: colorScheme), in: .rect(cornerRadius: BrandRadius.tile(BrandMetrics.tileLarge), style: .continuous))
                Spacer()
                Circle().fill(statusColor).frame(width: BrandMetrics.statusDot, height: BrandMetrics.statusDot)
                    .accessibilityHidden(true)
            }
            VStack(alignment: .leading, spacing: BrandMetrics.titleDetailSpacing) {
                Text(title).font(.headline)
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
            Text(status.presentationLabel)
                .font(.callout.weight(.semibold))
                .foregroundStyle(statusColor)
            if let statusDetail = status.detailLabel {
                Text(statusDetail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Spacer(minLength: 0)
            if let actionTitle {
                Button(actionTitle, action: action)
                    .auraButton(prominent: true)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 155, alignment: .leading)
        .padding(BrandMetrics.cardPadding)
        .auraCard(elevated: true)
        .accessibilityElement(children: .contain)
    }

    private var statusColor: Color {
        status.tintColor
    }
}

private struct PersistenceRecoveryBanner: View {
    @Environment(AppModel.self) private var model
    let message: String
    @State private var confirmingEmptySession = false

    var body: some View {
        HStack(spacing: BrandMetrics.gridSpacing) {
            Image(systemName: "externaldrive.badge.exclamationmark").foregroundStyle(BrandColors.warning)
            VStack(alignment: .leading, spacing: BrandMetrics.titleDetailSpacing) {
                Text("Local data needs recovery").font(.headline)
                Text(message).font(.caption).lineLimit(3)
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
        .padding(.horizontal, BrandSpacing.md)
        .padding(.vertical, BrandMetrics.cardPaddingCompact)
        .background(.bar)
        .accessibilityElement(children: .contain)
        .overlay(alignment: .bottomLeading) {
            if !model.persistenceRecoveryStatus.isEmpty {
                Text(model.persistenceRecoveryStatus).font(.caption).foregroundStyle(.secondary).padding(.leading, 46).offset(y: 11)
            }
        }
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

private extension String {
    var queueDisplayName: String {
        switch self {
        case "permanentlyFailed": "Needs attention";
        case "retrying": "Retrying";
        case "pending": "Waiting";
        default: capitalized
        }
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
