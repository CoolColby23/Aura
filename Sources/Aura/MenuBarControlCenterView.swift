import AppKit
import SwiftData
import SwiftUI

/// The menu-bar panel. It borrows Control Center's grammar — modules on the
/// system material, round toggles that fill when on — so it reads as part of
/// the Mac rather than a miniature copy of the dashboard.
struct MenuBarControlCenterView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openWindow) private var openWindow
    @Environment(\.appTheme) private var theme
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        @Bindable var preferences = model.preferences
        VStack(spacing: BrandSpacing.sm) {
            header
            MenuBarNowPlayingModule()
            HStack(spacing: BrandSpacing.sm) {
                MenuModuleTile(
                    name: "Discord",
                    symbol: "bubble.left.and.bubble.right.fill",
                    detail: model.isPrivate && preferences.discordEnabled ? "Paused" : model.discordStatus.presentationLabel,
                    isOn: Binding(get: { preferences.discordEnabled }, set: { model.setDiscordEnabled($0) })
                )
                MenuModuleTile(
                    name: "Last.fm",
                    symbol: "dot.radiowaves.left.and.right",
                    detail: model.isPrivate && preferences.lastFMEnabled ? "Paused" : model.lastFMStatus.presentationLabel,
                    isOn: Binding(get: { preferences.lastFMEnabled }, set: { model.setLastFMEnabled($0) })
                )
            }
            privateModeModule
            if preferences.menuBarExpanded {
                MenuBarWeeklyRecapView()
            }
            footer
        }
        .padding(BrandSpacing.sm)
        .frame(width: 340)
        .fixedSize(horizontal: false, vertical: true)
        .task { model.start() }
    }

    private var header: some View {
        HStack(spacing: BrandSpacing.sm) {
            SweepingBrandMark(isPlaying: model.snapshot.state == .playing && !model.isPrivate)
                .frame(width: 22, height: 22)
            VStack(alignment: .leading, spacing: 0) {
                Text("Aura").font(.headline)
                Text(statusLine)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            Button {
                withAnimation(.easeInOut(duration: 0.2)) { model.preferences.menuBarExpanded.toggle() }
            } label: {
                Image(systemName: model.preferences.menuBarExpanded ? "chevron.up" : "chevron.down")
                    .font(.caption.weight(.bold))
                    .frame(width: 24, height: 24)
                    .contentShape(.circle)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help(model.preferences.menuBarExpanded ? "Show less" : "Show this week’s recap")
            .accessibilityLabel(model.preferences.menuBarExpanded ? "Use compact menu" : "Use expanded menu")
        }
        .padding(.horizontal, BrandSpacing.xs)
        .padding(.top, 2)
    }

    private var statusLine: String {
        if model.isPrivate { return "Private — nothing is shared" }
        switch model.snapshot.state {
        case .playing: return "Listening on \(model.snapshot.track?.platform.rawValue ?? "your Mac")"
        case .paused: return "Paused"
        case .stopped: return "Watching for music"
        }
    }

    private var privateModeModule: some View {
        HStack(spacing: BrandMetrics.cardContentSpacing) {
            ModuleToggleCircle(
                symbol: model.isPrivate ? "eye.slash.fill" : "eye.slash",
                isOn: model.isPrivate,
                tint: BrandColors.warning
            ) {
                model.isPrivate ? model.endPrivateMode() : model.setPrivate(until: nil)
            }
            .accessibilityLabel(model.isPrivate ? "End Private Mode" : "Go Private until resumed")
            VStack(alignment: .leading, spacing: 1) {
                Text("Private Mode").font(.callout.weight(.semibold))
                Text(privateDetail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            if !model.isPrivate {
                Menu {
                    Button("For 15 Minutes") { model.setPrivate(until: .now.addingTimeInterval(900)) }
                    Button("For 1 Hour") { model.setPrivate(until: .now.addingTimeInterval(3_600)) }
                    Button("Until Resumed") { model.setPrivate(until: nil) }
                } label: {
                    Image(systemName: "clock")
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .foregroundStyle(.secondary)
                .help("Go private for a while")
                .accessibilityLabel("Go private for a set time")
            }
        }
        .padding(BrandMetrics.cardPaddingCompact)
        .auraSurface(.inset, radius: BrandRadius.md)
    }

    private var privateDetail: String {
        guard model.isPrivate else { return "Pause sharing for a while" }
        if let until = model.privateUntil { return "On until \(until.formatted(date: .omitted, time: .shortened))" }
        return "On until you resume"
    }

    private var footer: some View {
        HStack(spacing: BrandSpacing.xs) {
            Button {
                NSApp.showDashboard(using: openWindow)
            } label: {
                Label("Open Aura", systemImage: "macwindow")
                    .frame(maxWidth: .infinity)
            }
            .accessibilityIdentifier("menu.dashboard")
            SettingsLink {
                Label("Settings", systemImage: "gearshape")
                    .labelStyle(.iconOnly)
            }
            .help("Settings")
            .accessibilityIdentifier("menu.settings")
            Button("Quit Aura", systemImage: "power") {
                model.shutdown()
                NSApp.terminate(nil)
            }
            .labelStyle(.iconOnly)
            .help("Quit Aura")
        }
        .auraButton()
        .controlSize(.large)
    }
}

private struct MenuBarNowPlayingModule: View {
    @Environment(AppModel.self) private var model
    @Environment(\.appTheme) private var theme
    @State private var seekPosition: TimeInterval = 0
    @State private var isSeeking = false

    var body: some View {
        let isPlaying = model.snapshot.state == .playing
        VStack(spacing: BrandMetrics.cardContentSpacing) {
            HStack(spacing: BrandMetrics.cardContentSpacing) {
                ArtworkAura(cornerRadius: 60 * ArtworkView.cornerRatio, isPlaying: isPlaying) {
                    ArtworkView(image: model.artworkImage, size: 60, isPlaying: isPlaying)
                }
                VStack(alignment: .leading, spacing: 1) {
                    if let track = model.snapshot.track {
                        Text(track.title)
                            .font(.headline)
                            .lineLimit(1)
                        Text([track.artist, track.album].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · "))
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                        HStack(spacing: 5) {
                            StatusDot(tint: isPlaying ? BrandColors.blush : BrandColors.neutral, size: 6)
                            Text(isPlaying ? track.platform.rawValue : "Paused")
                        }
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .padding(.top, 2)
                    } else {
                        Text("Nothing playing").font(.headline)
                        Text("Start a song in a supported app.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 0)
            }

            if let track = model.snapshot.track, track.supportsFiniteProgress {
                if model.canControlPlayback {
                    seekControl(duration: track.duration)
                } else {
                    PlaybackProgress(snapshot: model.snapshot, duration: track.duration)
                }
            }

            if model.canControlPlayback {
                transport
            }
        }
        .padding(BrandMetrics.cardPaddingCompact)
        .auraSurface(.inset, radius: BrandRadius.md)
        .onChange(of: model.snapshot.position) { _, position in
            if !isSeeking { seekPosition = position }
        }
        .onAppear { seekPosition = model.snapshot.position }
    }

    private var transport: some View {
        HStack(spacing: 0) {
            iconButton("speaker.minus.fill", label: "Lower Volume", size: 12) { model.adjustPlaybackVolume(by: -10) }
            Spacer()
            TransportButton(title: "Previous Track", symbol: "backward.fill", diameter: 34) {
                model.performPlaybackControl(.previous)
            }
            Spacer()
            TransportButton(
                title: model.snapshot.state == .playing ? "Pause" : "Play",
                symbol: model.snapshot.state == .playing ? "pause.fill" : "play.fill",
                diameter: 44,
                prominent: true
            ) {
                model.performPlaybackControl(.toggle)
            }
            Spacer()
            TransportButton(title: "Next Track", symbol: "forward.fill", diameter: 34) {
                model.performPlaybackControl(.next)
            }
            Spacer()
            iconButton("speaker.plus.fill", label: "Raise Volume", size: 12) { model.adjustPlaybackVolume(by: 10) }
        }
        .padding(.horizontal, BrandSpacing.xs)
    }

    private func iconButton(_ symbol: String, label: String, size: CGFloat, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: size, weight: .semibold))
                .frame(width: 32, height: 32)
                .contentShape(.circle)
        }
        .buttonStyle(.plain)
        .foregroundStyle(.primary.opacity(0.8))
        .help(label)
        .accessibilityLabel(label)
    }

    private func seekControl(duration: TimeInterval) -> some View {
        VStack(spacing: 2) {
            Slider(value: $seekPosition, in: 0...max(duration, 1)) { editing in
                isSeeking = editing
                if !editing { model.seekPlayback(to: seekPosition) }
            }
            .controlSize(.small)
            .tint(theme.primaryColor)
            .accessibilityLabel("Playback position")
            .accessibilityValue("\(Int(seekPosition)) seconds of \(Int(duration)) seconds")
            HStack {
                Text(seekPosition.formattedDuration)
                Spacer()
                Text("−\(max(0, duration - seekPosition).formattedDuration)")
            }
            .font(.caption2.monospacedDigit())
            .foregroundStyle(.secondary)
        }
    }
}

private struct MenuModuleTile: View {
    let name: String
    let symbol: String
    let detail: String
    @Binding var isOn: Bool

    var body: some View {
        HStack(spacing: BrandSpacing.sm) {
            ModuleToggleCircle(symbol: symbol, isOn: isOn) { isOn.toggle() }
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                Text(name).font(.callout.weight(.semibold))
                Text(isOn ? detail : "Off")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(BrandMetrics.cardPaddingCompact)
        .frame(maxWidth: .infinity, alignment: .leading)
        .auraSurface(.inset, radius: BrandRadius.md)
        .contentShape(.rect)
        .onTapGesture { isOn.toggle() }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(name)
        .accessibilityValue(isOn ? detail : "Off")
        .accessibilityAddTraits(.isToggle)
        .accessibilityAction { isOn.toggle() }
    }
}

private struct MenuBarWeeklyRecapView: View {
    @Query(sort: \ActivityRecord.startedAt, order: .reverse) private var records: [ActivityRecord]

    var body: some View {
        let recap = WeeklyListeningRecap(records: records)
        VStack(alignment: .leading, spacing: BrandSpacing.sm) {
            HStack {
                Text("This week")
                    .auraEyebrow()
                    .foregroundStyle(.secondary)
                Spacer()
                if recap.listens > 0 {
                    Button("Copy Recap", systemImage: "doc.on.doc") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(recap.shareText, forType: .string)
                    }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.borderless)
                    .help("Copy this week’s recap")
                }
            }
            HStack(spacing: 0) {
                recapMetric(recap.listens.formatted(), "listens")
                recapMetric(recap.minutes.formatted(), "minutes")
                recapMetric(recap.uniqueArtists.formatted(), "artists")
            }
            if let artist = recap.topArtist {
                Text("Most played: \(artist)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(BrandMetrics.cardPaddingCompact)
        .auraSurface(.inset, radius: BrandRadius.md)
        .transition(.opacity.combined(with: .move(edge: .top)))
    }

    private func recapMetric(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(value).font(.system(size: 20, weight: .semibold, design: .rounded).monospacedDigit())
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}
