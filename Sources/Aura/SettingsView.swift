import SwiftUI

enum SettingsCategory: String, CaseIterable, Identifiable {
    case general = "General"
    case appearance = "Appearance"
    case players = "Players"
    case discord = "Discord"
    case lastFM = "Last.fm"
    case data = "Data"
    case advanced = "Advanced"

    var id: Self { self }
    var detail: String {
        switch self {
        case .general: "Startup, the sidebar, demo playback, and updates"
        case .appearance: "How Aura looks in light and dark mode"
        case .players: "Which music apps Aura watches, and in what order"
        case .discord: "Rich Presence: what appears on your profile and how"
        case .lastFM: "Scrobbling, your account, and what never gets sent"
        case .data: "Local history, backups, and encrypted iCloud copies"
        case .advanced: "Developer overrides and specialized options"
        }
    }
    var symbol: String {
        switch self {
        case .general: "gearshape"
        case .appearance: "paintpalette"
        case .players: "music.note.list"
        case .discord: "bubble.left.and.bubble.right"
        case .lastFM: "dot.radiowaves.left.and.right"
        case .data: "externaldrive"
        case .advanced: "wrench.and.screwdriver"
        }
    }
}

/// Settings inside the dashboard. The category comes from the main sidebar.
struct SettingsView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        SettingsPane(category: model.selectedSettingsCategory, showsHeader: true)
            .id(model.selectedSettingsCategory)
    }
}

/// The standalone Settings window (⌘,). Native toolbar tabs over the same panes
/// the dashboard shows, so both routes lead to identical controls.
struct SettingsWindowView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        TabView(selection: $model.selectedSettingsCategory) {
            ForEach(SettingsCategory.allCases) { category in
                Tab(category.rawValue, systemImage: category.symbol, value: category) {
                    SettingsPane(category: category, showsHeader: false)
                }
            }
        }
        .scenePadding(.minimum)
    }
}

private struct SettingsPane: View {
    let category: SettingsCategory
    let showsHeader: Bool
    @Environment(AppModel.self) private var model
    @Environment(UpdateManager.self) private var updateManager
    @State private var backupDocument: AuraBackupDocument?
    @State private var showingBackupExporter = false
    @State private var showingBackupImporter = false
    @State private var pendingRestore: AuraBackup?
    @State private var showingRestoreConfirmation = false
    @State private var showingDisconnectConfirmation = false
    @State private var dataStatus = ""

    var body: some View {
        Form {
            if showsHeader {
                // The grouped form centers its rows in a fixed measure, so the
                // heading lives inside the form as the footer of a rowless
                // section: it then shares the rows' leading edge instead of
                // hugging the pane. (A header would merge with the next section's.)
                Section {
                } footer: {
                    SettingsHeader(category: category)
                }
            }
            switch category {
            case .general:
                GeneralSettingsSections(model: model, updateManager: updateManager)
            case .appearance:
                AppearanceSettingsSections()
            case .players:
                PlaybackProviderSettingsSection(model: model, preferences: model.preferences)
            case .discord:
                DiscordSettingsSections(model: model, preferences: model.preferences)
            case .lastFM:
                LastFMSettingsSections(
                    model: model,
                    preferences: model.preferences,
                    disconnect: { showingDisconnectConfirmation = true }
                )
            case .data:
                DataSettingsSections(
                    model: model,
                    preferences: model.preferences,
                    dataStatus: dataStatus,
                    prepareBackup: prepareBackup,
                    restoreBackup: { showingBackupImporter = true },
                    confirmCloudRestore: {
                        pendingRestore = $0
                        showingRestoreConfirmation = true
                    }
                )
            case .advanced:
                AdvancedSettingsSection(model: model)
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .environment(model)
        .fileExporter(
            isPresented: $showingBackupExporter,
            document: backupDocument,
            contentType: .auraBackup,
            defaultFilename: "Aura-Backup.aurabackup",
            onCompletion: finishBackupExport
        )
        .fileImporter(
            isPresented: $showingBackupImporter,
            allowedContentTypes: [.auraBackup, .json],
            onCompletion: importBackup
        )
        .confirmationDialog(
            "Replace current Aura data?",
            isPresented: $showingRestoreConfirmation,
            titleVisibility: .visible
        ) {
            Button("Restore and Replace", role: .destructive, action: restorePendingBackup)
            Button("Cancel", role: .cancel) { pendingRestore = nil }
        } message: {
            Text(
                "Aura will first create an automatic local backup, then replace listening history, queued scrobbles, and non-secret settings. Credentials are never imported."
            )
        }
        .confirmationDialog(
            "Disconnect Last.fm?",
            isPresented: $showingDisconnectConfirmation,
            titleVisibility: .visible
        ) {
            Button("Disconnect Last.fm", role: .destructive, action: disconnectLastFM)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Aura will stop scrobbling and remove the saved Last.fm authorization. Your Last.fm account and listening history are not deleted.")
        }
    }

    private func prepareBackup() {
        do {
            backupDocument = AuraBackupDocument(
                backup: try BackupService.make(store: model.store, preferences: model.preferences)
            )
            showingBackupExporter = true
        } catch { dataStatus = error.localizedDescription }
    }

    private func finishBackupExport(_ result: Result<URL, any Error>) {
        if case .success = result {
            model.preferences.lastBackupAt = .now
            dataStatus = "Backup saved."
        } else if case .failure(let error) = result {
            dataStatus = error.localizedDescription
        }
        backupDocument = nil
    }

    private func importBackup(_ result: Result<URL, any Error>) {
        do {
            let url = try result.get()
            let accessed = url.startAccessingSecurityScopedResource()
            defer { if accessed { url.stopAccessingSecurityScopedResource() } }
            let backup = try BackupService.decode(Data(contentsOf: url))
            try BackupService.validate(backup)
            pendingRestore = backup
            showingRestoreConfirmation = true
        } catch { dataStatus = error.localizedDescription }
    }

    private func restorePendingBackup() {
        guard let pendingRestore else { return }
        do {
            try BackupService.restore(pendingRestore, store: model.store, preferences: model.preferences)
            dataStatus = "Backup restored. Reconnect Last.fm if needed."
        } catch { dataStatus = error.localizedDescription }
        self.pendingRestore = nil
    }

    private func disconnectLastFM() {
        model.preferences.lastFMEnabled = false
        Task { await model.disconnectLastFM() }
    }
}

private struct SettingsHeader: View {
    let category: SettingsCategory
    @Environment(\.appTheme) private var theme

    var body: some View {
        HStack(spacing: BrandMetrics.cardContentSpacing) {
            SymbolTile(symbol: category.symbol, tint: theme.primaryColor, size: 44, filled: true)
            VStack(alignment: .leading, spacing: BrandMetrics.titleDetailSpacing) {
                Text(category.rawValue)
                    .font(BrandTypography.pageTitle)
                    .foregroundStyle(.primary)
                Text(category.detail)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        // Footers sit 8 points outside the section headers' text edge.
        .padding(.leading, 8)
        .padding(.bottom, BrandSpacing.xs)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}

/// A caption beneath a group of settings rows.
private struct SettingsFootnote: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// A row that names a connection and states its status in words and color.
struct SettingsStatusRow: View {
    let title: String
    let detail: String
    let status: ServiceStatus

    var body: some View {
        HStack(spacing: BrandMetrics.cardContentSpacing) {
            VStack(alignment: .leading, spacing: BrandMetrics.titleDetailSpacing) {
                Text(title)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            StatusPill(title: status.presentationLabel, symbol: status.symbol, tint: status.tintColor)
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - General

private struct GeneralSettingsSections: View {
    let model: AppModel
    let updateManager: UpdateManager

    var body: some View {
        @Bindable var preferences = model.preferences
        @Bindable var updateManager = updateManager
        Section("Startup") {
            Toggle("Open Aura at login", isOn: $preferences.launchAtLogin)
                .onChange(of: preferences.launchAtLogin) { _, value in model.setLaunchAtLogin(value) }
            LabeledContent("Setup guide") {
                Button("Show Again") { model.onboardingPresented = true }
            }
        }
        Section {
            ForEach(DashboardSection.allCases.filter(\.canBeHidden)) { section in
                Toggle(isOn: sidebarBinding(section)) {
                    Label(section.title, systemImage: section.symbol)
                }
            }
        } header: {
            Text("Sidebar")
        } footer: {
            SettingsFootnote("Now Playing and Settings always stay in the sidebar. Hidden pages remain reachable from Quick Open (⌘K).")
        }
        Section {
            Toggle("Simulate playback for a product tour", isOn: demoModeBinding)
        } header: {
            Text("Demo Mode")
        } footer: {
            SettingsFootnote(
                "Runs short sample tracks through the real now-playing and local-history pipeline. Discord and Last.fm publishing are paused, and sample history is removed when the demo ends."
            )
        }
        Section {
            Toggle("Check for updates automatically", isOn: $updateManager.automaticallyChecksForUpdates)
            Toggle("Download updates automatically", isOn: $updateManager.automaticallyDownloadsUpdates)
                .disabled(!updateManager.automaticallyChecksForUpdates)
            LabeledContent("Version \(ReleaseConfiguration.version) (\(ReleaseConfiguration.build))") {
                Button("Check for Updates…") { updateManager.checkForUpdates() }
            }
        } header: {
            Text("Updates")
        } footer: {
            SettingsFootnote("Updates come from official Aura GitHub releases and are verified before installation.")
        }
    }

    private func sidebarBinding(_ section: DashboardSection) -> Binding<Bool> {
        Binding(
            get: { model.preferences.isDashboardSectionVisible(section) },
            set: { visible in
                if visible != model.preferences.isDashboardSectionVisible(section) {
                    model.preferences.toggleDashboardSection(section)
                }
            }
        )
    }

    private var demoModeBinding: Binding<Bool> {
        Binding(get: { model.demoModeEnabled }, set: { model.setDemoModeEnabled($0) })
    }
}

// MARK: - Last.fm

private struct LastFMSettingsSections: View {
    let model: AppModel
    let preferences: Preferences
    let disconnect: () -> Void

    var body: some View {
        @Bindable var model = model
        @Bindable var preferences = preferences
        Section("Account") {
            SettingsStatusRow(
                title: model.lastFMUsername.isEmpty ? "Last.fm" : model.lastFMUsername,
                detail: model.lastFMUsername.isEmpty ? "Not connected yet" : "Connected account",
                status: model.lastFMStatus
            )
            if !model.lastFMUsername.isEmpty {
                LabeledContent("Authorization") {
                    Button("Disconnect…", role: .destructive, action: disconnect)
                }
            }
        }
        if model.lastFMUsername.isEmpty {
            Section {
                SetupStep(number: 1, title: "Add your API credentials", done: model.hasStoredLastFMCredentials) {
                    SecureField("API key", text: $model.credentialDraft.lastFMAPIKey, prompt: Text("API key"))
                        .textFieldStyle(.roundedBorder)
                        .labelsHidden()
                    SecureField("Shared secret", text: $model.credentialDraft.lastFMSecret, prompt: Text("Shared secret"))
                        .textFieldStyle(.roundedBorder)
                        .labelsHidden()
                    HStack {
                        Button("Save Credentials") { Task { await model.saveCredentials() } }
                            .disabled(model.credentialDraft.lastFMAPIKey.isEmpty && model.credentialDraft.lastFMSecret.isEmpty)
                        Spacer()
                    }
                }
                SetupStep(number: 2, title: "Authorize Aura in your browser", done: model.lastFMStatus == .connecting) {
                    HStack {
                        Button("Authorize in Browser") { Task { await model.beginLastFMAuthorization() } }
                            .disabled(
                                !model.hasStoredLastFMCredentials
                                    && (model.credentialDraft.lastFMAPIKey.isEmpty
                                        || model.credentialDraft.lastFMSecret.isEmpty)
                            )
                        Spacer()
                    }
                }
                SetupStep(number: 3, title: "Come back and finish", done: false) {
                    HStack {
                        Button("Complete Authorization") { Task { await model.completeLastFMAuthorization() } }
                            .auraButton(prominent: true)
                        Spacer()
                    }
                }
            } header: {
                Text("Connect Last.fm")
            } footer: {
                SettingsFootnote("Blank fields keep an existing saved value. Aura never displays your stored shared secret.")
            }
        }
        Section("Scrobbling") {
            Toggle("Scrobble finished listens", isOn: $preferences.lastFMEnabled)
                .onChange(of: preferences.lastFMEnabled) { _, value in model.setLastFMEnabled(value) }
            Toggle("Show what’s playing on your profile", isOn: $preferences.sendNowPlaying)
        }
        Section {
            TextField(
                "Artists",
                text: $preferences.excludedScrobbleArtists,
                prompt: Text("One per line, or comma-separated"),
                axis: .vertical
            )
            TextField(
                "Albums",
                text: $preferences.excludedScrobbleAlbums,
                prompt: Text("One per line, or comma-separated"),
                axis: .vertical
            )
            TextField(
                "Titles containing",
                text: $preferences.excludedScrobbleTitleTerms,
                prompt: Text("One term per line, or comma-separated"),
                axis: .vertical
            )
            ForEach(PlaybackPlatform.allCases) { platform in
                Toggle("Skip everything from \(platform.rawValue)", isOn: exclusionBinding(for: platform))
            }
        } header: {
            Text("Never Scrobble")
        } footer: {
            SettingsFootnote("Exclusions affect Last.fm only. Listening History and Discord are unchanged.")
        }
        .onChange(of: preferences.excludedScrobbleArtists) { _, _ in model.refreshScrobbleRules() }
        .onChange(of: preferences.excludedScrobbleAlbums) { _, _ in model.refreshScrobbleRules() }
        .onChange(of: preferences.excludedScrobbleTitleTerms) { _, _ in model.refreshScrobbleRules() }
        .onChange(of: preferences.excludedScrobblePlatforms) { _, _ in model.refreshScrobbleRules() }
    }

    private func exclusionBinding(for platform: PlaybackPlatform) -> Binding<Bool> {
        Binding(
            get: { preferences.excludedScrobblePlatforms.contains(platform) },
            set: { excluded in
                if excluded {
                    preferences.excludedScrobblePlatforms.insert(platform)
                } else {
                    preferences.excludedScrobblePlatforms.remove(platform)
                }
            }
        )
    }
}

/// One numbered step in a connection flow. The number becomes a check once the
/// step is done, so progress is legible without reading every row.
private struct SetupStep<Content: View>: View {
    let number: Int
    let title: String
    let done: Bool
    @ViewBuilder var content: Content
    @Environment(\.appTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: BrandSpacing.sm) {
            HStack(spacing: BrandSpacing.sm) {
                ZStack {
                    Circle().fill(done ? AnyShapeStyle(BrandColors.success) : AnyShapeStyle(theme.primaryColor.opacity(0.14)))
                    if done {
                        Image(systemName: "checkmark").font(.caption2.weight(.bold)).foregroundStyle(.white)
                    } else {
                        Text("\(number)").font(.caption.weight(.bold).monospacedDigit()).foregroundStyle(theme.primaryColor)
                    }
                }
                .frame(width: 22, height: 22)
                .accessibilityHidden(true)
                Text(title).font(.callout.weight(.semibold))
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Step \(number): \(title)\(done ? ", done" : "")")
            VStack(alignment: .leading, spacing: BrandSpacing.sm) {
                content
            }
            .padding(.leading, 30)
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Players

private struct PlaybackProviderSettingsSection: View {
    let model: AppModel
    let preferences: Preferences

    var body: some View {
        Section {
            ForEach(Array(preferences.playbackProviderOrder.enumerated()), id: \.element) { index, provider in
                PlaybackProviderRow(
                    rank: index + 1,
                    provider: provider,
                    isEnabled: providerBinding(provider),
                    canMoveUp: index > 0,
                    canMoveDown: index < preferences.playbackProviderOrder.count - 1,
                    moveUp: { model.movePlaybackProvider(provider, by: -1) },
                    moveDown: { model.movePlaybackProvider(provider, by: 1) }
                )
            }
        } header: {
            Text("Music Players")
        } footer: {
            SettingsFootnote(
                "Aura stays with whichever player is actively playing. When several start together, the higher one wins. TIDAL is best effort through macOS Now Playing."
            )
        }
        if preferences.enabledPlaybackProviders.contains(.youtubeMusic) {
            Section {
                SettingsStatusRow(
                    title: "YTMDesktop Companion Server",
                    detail: "Required to read YouTube Music",
                    status: model.ytmDesktopStatus
                )
                LabeledContent("Connection") {
                    Button(model.ytmDesktopStatus == .connected ? "Disconnect" : "Connect") {
                        Task {
                            if model.ytmDesktopStatus == .connected {
                                await model.disconnectYTMDesktop()
                            } else {
                                await model.connectYTMDesktop()
                            }
                        }
                    }
                }
            } header: {
                Text("YouTube Music")
            } footer: {
                SettingsFootnote("Turn on the Companion Server in YTMDesktop’s settings, then connect and approve Aura there.")
            }
        }
    }

    private func providerBinding(_ provider: PlaybackProviderID) -> Binding<Bool> {
        Binding(
            get: { preferences.enabledPlaybackProviders.contains(provider) },
            set: { model.setPlaybackProvider(provider, enabled: $0) }
        )
    }
}

private struct PlaybackProviderRow: View {
    let rank: Int
    let provider: PlaybackProviderID
    @Binding var isEnabled: Bool
    let canMoveUp: Bool
    let canMoveDown: Bool
    let moveUp: () -> Void
    let moveDown: () -> Void
    @Environment(\.appTheme) private var theme
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(spacing: BrandMetrics.cardContentSpacing) {
            Text("\(rank)")
                .font(.callout.weight(.bold).monospacedDigit())
                .foregroundStyle(isEnabled ? theme.readablePrimary(for: colorScheme) : Color.secondary)
                .frame(width: 16)
                .accessibilityHidden(true)
            Toggle(provider.displayName, isOn: $isEnabled)
            Spacer()
            ControlGroup {
                Button(action: moveUp) { Image(systemName: "chevron.up") }
                    .disabled(!canMoveUp)
                    .accessibilityLabel(provider.moveEarlierAccessibilityLabel)
                    .accessibilityIdentifier("players.\(provider.rawValue).move-up")
                Button(action: moveDown) { Image(systemName: "chevron.down") }
                    .disabled(!canMoveDown)
                    .accessibilityLabel(provider.moveLaterAccessibilityLabel)
                    .accessibilityIdentifier("players.\(provider.rawValue).move-down")
            }
            .controlSize(.small)
            .fixedSize()
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("players.\(provider.rawValue)")
    }
}

// MARK: - Data

private struct DataSettingsSections: View {
    let model: AppModel
    let preferences: Preferences
    let dataStatus: String
    let prepareBackup: () -> Void
    let restoreBackup: () -> Void
    let confirmCloudRestore: (AuraBackup) -> Void
    @State private var cloudPassphrase = ""
    @State private var cloudStatus = ""
    @State private var cloudOperationInProgress = false

    var body: some View {
        @Bindable var preferences = preferences
        Section {
            Picker("Keep history for", selection: $preferences.historyRetentionDays) {
                Text("30 days").tag(30)
                Text("90 days").tag(90)
                Text("1 year").tag(365)
                Text("Forever").tag(0)
            }
            .onChange(of: preferences.historyRetentionDays) { _, _ in model.applyHistoryRetention() }
        } header: {
            Text("Listening History")
        } footer: {
            SettingsFootnote("History stays on this Mac and is never uploaded by Aura.")
        }
        Section {
            LabeledContent("Back up to a file") {
                Button("Back Up…", action: prepareBackup)
            }
            LabeledContent("Restore from a file") {
                Button("Restore…", action: restoreBackup)
            }
            if let date = preferences.lastBackupAt {
                LabeledContent("Last backup", value: date.formatted(date: .abbreviated, time: .shortened))
            }
            if !dataStatus.isEmpty {
                Text(dataStatus).font(.callout).foregroundStyle(.secondary)
            }
        } header: {
            Text("Backup and Restore")
        } footer: {
            SettingsFootnote(
                "Backups contain listening history, the scrobble queue, and non-secret settings. Credentials, authorization tokens, diagnostics, artwork, and machine-specific paths are left out. Restoring replaces current local data and disconnects Last.fm."
            )
        }
        Section {
            SecureField("Passphrase", text: $cloudPassphrase, prompt: Text("At least 12 characters"))
                .textContentType(.newPassword)
            HStack {
                Button("Back Up to iCloud", systemImage: "icloud.and.arrow.up") { createCloudBackup() }
                Button("Restore from iCloud", systemImage: "icloud.and.arrow.down") { restoreCloudBackup() }
                Spacer()
                if cloudOperationInProgress { ProgressView().controlSize(.small) }
            }
            .disabled(cloudOperationInProgress || cloudPassphrase.count < 12)
            if !cloudStatus.isEmpty {
                Text(cloudStatus).font(.callout).foregroundStyle(.secondary)
            }
        } header: {
            Text("Encrypted iCloud Backup")
        } footer: {
            SettingsFootnote(
                "Backups use authenticated AES-256-GCM encryption. Your passphrase is never stored and cannot be recovered. iCloud Drive requires an entitled Aura build."
            )
        }
    }

    private func createCloudBackup() {
        do {
            let data = try BackupService.encode(
                BackupService.make(store: model.store, preferences: preferences)
            )
            let passphrase = cloudPassphrase
            cloudOperationInProgress = true
            cloudStatus = "Encrypting backup…"
            Task {
                do {
                    let url = try await Task.detached {
                        try ICloudBackupStore.save(
                            SecureBackupService.encrypt(data, passphrase: passphrase)
                        )
                    }.value
                    preferences.lastBackupAt = .now
                    cloudStatus = "Encrypted backup saved to iCloud Drive as \(url.lastPathComponent)."
                } catch { cloudStatus = error.localizedDescription }
                cloudOperationInProgress = false
            }
        } catch { cloudStatus = error.localizedDescription }
    }

    private func restoreCloudBackup() {
        let passphrase = cloudPassphrase
        cloudOperationInProgress = true
        cloudStatus = "Downloading and decrypting backup…"
        Task {
            do {
                let backup = try await Task.detached {
                    let encrypted = try ICloudBackupStore.loadLatest()
                    let data = try SecureBackupService.decrypt(encrypted, passphrase: passphrase)
                    let backup = try BackupService.decode(data)
                    try BackupService.validate(backup)
                    return backup
                }.value
                cloudStatus = "Backup decrypted. Confirm restore to continue."
                confirmCloudRestore(backup)
            } catch { cloudStatus = error.localizedDescription }
            cloudOperationInProgress = false
        }
    }
}

// MARK: - Advanced

private struct AdvancedSettingsSection: View {
    let model: AppModel

    var body: some View {
        @Bindable var model = model
        Section {
            SecureField("Application ID", text: $model.credentialDraft.discordApplicationID, prompt: Text("Official Aura application"))
            LabeledContent("Override") {
                Button("Save Override") { Task { await model.saveCredentials() } }
            }
        } header: {
            Text("Custom Discord Application")
        } footer: {
            SettingsFootnote(
                "The override is stored in Aura’s private local settings. Leave it empty to use the official Aura Discord application."
            )
        }
    }
}
