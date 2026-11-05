import SwiftData
import SwiftUI

/// Everything the dashboard sidebar can select. Settings categories sit in the
/// same list as the pages, the way System Settings does it, so there is never a
/// second sidebar nested inside the first.
enum SidebarDestination: Hashable {
    case section(DashboardSection)
    case settings(SettingsCategory)
}

struct DashboardView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        NavigationSplitView {
            DashboardSidebar()
                .navigationSplitViewColumnWidth(min: 214, ideal: 236, max: 300)
        } detail: {
            detail
                .toolbar(removing: .title)
                .toolbar {
                    ToolbarItem(placement: .navigation) {
                        Button("Quick Open", systemImage: "command") {
                            model.commandPalettePresented = true
                        }
                        .help("Quick Open (⌘K)")
                    }
                }
        }
        .task { model.start() }
        .sheet(isPresented: $model.onboardingPresented) { OnboardingView().environment(model) }
        .sheet(isPresented: $model.commandPalettePresented) {
            CommandPaletteView().environment(model)
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            if let issue = model.persistenceIssue {
                PersistenceRecoveryBanner(message: issue)
            }
        }
        .frame(minWidth: DashboardLayout.minimumWidth, minHeight: DashboardLayout.minimumHeight)
    }

    @ViewBuilder
    private var detail: some View {
        Group {
            switch model.selectedSection {
            case .nowPlaying: NowPlayingView()
            case .history: ListeningHistoryView()
            case .queue: QueueView()
            case .diagnostics: DiagnosticsView()
            case .settings: SettingsView()
            }
        }
        .environment(model)
        .auraPanelBackground()
        .navigationTitle(detailTitle)
    }

    /// Still set for the Window menu and VoiceOver, even though the toolbar no
    /// longer shows it — each page opens with its own large title instead.
    private var detailTitle: String {
        model.selectedSection == .settings ? model.selectedSettingsCategory.rawValue : model.selectedSection.title
    }
}

private struct DashboardSidebar: View {
    @Environment(AppModel.self) private var model
    @Environment(\.appTheme) private var theme
    @Query(filter: #Predicate<ScrobbleRecord> { $0.stateRaw != "submitted" }) private var pendingRecords: [ScrobbleRecord]
    @State private var settingsExpanded = true

    var body: some View {
        List(selection: selection) {
            Section("Listen") {
                ForEach(visibleSections([.nowPlaying, .history])) { section in
                    row(for: section)
                }
            }
            if !visibleSections([.queue, .diagnostics]).isEmpty {
                Section("Manage") {
                    ForEach(visibleSections([.queue, .diagnostics])) { section in
                        row(for: section)
                    }
                }
            }
            Section("Settings", isExpanded: $settingsExpanded) {
                ForEach(SettingsCategory.allCases) { category in
                    Label(category.rawValue, systemImage: category.symbol)
                        .tag(SidebarDestination.settings(category))
                        .accessibilityIdentifier("settings.category.\(category.id)")
                }
            }
        }
        .listStyle(.sidebar)
        .accessibilityIdentifier("dashboard.navigation")
        .safeAreaInset(edge: .top, spacing: 0) {
            SidebarHeader()
                .padding(.horizontal, BrandSpacing.md)
                .padding(.top, BrandSpacing.xs)
                .padding(.bottom, BrandSpacing.sm)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            SidebarPrivacyBar()
                .padding(.horizontal, BrandSpacing.sm)
                .padding(.bottom, BrandSpacing.sm)
        }
        .onChange(of: model.selectedSection) { _, section in
            if section == .settings { settingsExpanded = true }
        }
    }

    private func row(for section: DashboardSection) -> some View {
        Label(section.title, systemImage: section.symbol)
            .badge(section == .queue ? pendingRecords.count : 0)
            .tag(SidebarDestination.section(section))
            .accessibilityIdentifier("dashboard.section.\(section.id.rawValue)")
            .contextMenu {
                if section.canBeHidden {
                    Button("Hide from Sidebar", systemImage: "eye.slash") {
                        model.preferences.toggleDashboardSection(section)
                        if model.selectedSection == section { model.navigate(to: .nowPlaying) }
                    }
                }
            }
    }

    private var selection: Binding<SidebarDestination?> {
        Binding(
            get: {
                model.selectedSection == .settings
                    ? .settings(model.selectedSettingsCategory)
                    : .section(model.selectedSection)
            },
            set: { destination in
                switch destination {
                case .section(let section): model.navigate(to: section)
                case .settings(let category): model.openSettings(category)
                case nil: break
                }
            }
        )
    }

    private func visibleSections(_ sections: [DashboardSection]) -> [DashboardSection] {
        sections.filter(model.preferences.isDashboardSectionVisible)
    }
}

struct SidebarHeader: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        HStack(spacing: BrandSpacing.sm) {
            SweepingBrandMark(isPlaying: model.snapshot.state == .playing && !model.isPrivate)
                .frame(width: 30, height: 30)
            VStack(alignment: .leading, spacing: 1) {
                Text("Aura")
                    .font(BrandTypography.cardTitle)
                HStack(spacing: 5) {
                    StatusDot(tint: headerStatusColor, size: 6)
                    Text(headerDetail)
                        .lineLimit(1)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Aura, \(headerDetail)")
    }

    private var headerDetail: String {
        if model.isPrivate { return "Private Mode" }
        if model.snapshot.state == .playing, let platform = model.snapshot.track?.platform {
            return "Listening on \(platform.rawValue)"
        }
        if model.snapshot.state == .paused { return "Paused" }
        return "Watching for music"
    }

    private var headerStatusColor: Color {
        if model.isPrivate { return BrandColors.warning }
        return model.snapshot.state == .playing ? BrandColors.blush : BrandColors.neutral
    }
}

/// The one privacy control the dashboard always shows. Private Mode is meant to
/// be close at hand, so it lives at the foot of the sidebar on every page and
/// says plainly what is on.
struct SidebarPrivacyBar: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        HStack(spacing: BrandSpacing.sm) {
            ModuleToggleCircle(
                symbol: model.isPrivate ? "eye.slash.fill" : "eye.slash",
                isOn: model.isPrivate,
                tint: BrandColors.warning
            ) {
                model.isPrivate ? model.endPrivateMode() : model.setPrivate(until: nil)
            }
            .help(model.isPrivate ? "End Private Mode" : "Go Private until you resume")
            .accessibilityLabel(model.isPrivate ? "End Private Mode" : "Go Private")
            VStack(alignment: .leading, spacing: 1) {
                Text(model.isPrivate ? "Private" : "Sharing")
                    .font(.callout.weight(.semibold))
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            if !model.isPrivate {
                Menu {
                    Button("Private for 15 Minutes") { model.setPrivate(until: .now.addingTimeInterval(900)) }
                    Button("Private for 1 Hour") { model.setPrivate(until: .now.addingTimeInterval(3600)) }
                    Button("Private Until Resumed") { model.setPrivate(until: nil) }
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
        .padding(BrandSpacing.sm)
        .auraSurface(.inset, radius: BrandRadius.md)
        .accessibilityElement(children: .contain)
    }

    private var detail: String {
        if model.isPrivate {
            if let until = model.privateUntil { return "Until \(until.formatted(date: .omitted, time: .shortened))" }
            return "Until you resume"
        }
        return model.preferences.sharingSummary
    }
}

extension Preferences {
    /// What leaves the Mac right now, in the fewest words.
    var sharingSummary: String {
        switch (discordEnabled, lastFMEnabled) {
        case (true, true): "Discord · Last.fm"
        case (true, false): "Discord"
        case (false, true): "Last.fm"
        case (false, false): "Nothing is shared"
        }
    }
}
