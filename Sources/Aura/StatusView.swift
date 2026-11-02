import SwiftData
import SwiftUI

struct DiagnosticsView: View {
    @Environment(AppModel.self) private var model
    @Query(sort: \DiagnosticRecord.timestamp, order: .reverse) private var records: [DiagnosticRecord]
    @Query(sort: \IntegrationHealthEvent.timestamp, order: .reverse) private var healthEvents: [IntegrationHealthEvent]
    @State private var showsTechnicalDetails = false
    @State private var artworkCacheSummary = "Loading…"

    var body: some View {
        AuraPage(
            title: "Status & Support",
            subtitle: "What Aura can detect and share right now. Anything that needs you can be fixed from here."
        ) {
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 240), spacing: BrandMetrics.gridSpacing, alignment: .top)],
                alignment: .leading,
                spacing: BrandMetrics.gridSpacing
            ) {
                ConnectionStatusCard(
                    title: model.playbackServiceName,
                    role: "Music detection",
                    symbol: "music.note",
                    status: model.musicStatus,
                    lastConnected: nil,
                    actionTitle: model.musicStatus == .awaitingPermission ? "Allow Access" : nil,
                    action: model.openAutomationSettings
                )
                ConnectionStatusCard(
                    title: "Discord",
                    role: "Rich Presence",
                    symbol: "bubble.left.and.bubble.right.fill",
                    status: model.discordStatus,
                    lastConnected: lastConnected(.discord),
                    actionTitle: discordActionTitle,
                    action: model.refreshDiscord
                )
                ConnectionStatusCard(
                    title: "Last.fm",
                    role: "Scrobbling",
                    symbol: "dot.radiowaves.left.and.right",
                    status: model.lastFMStatus,
                    lastConnected: lastConnected(.lastFM),
                    actionTitle: lastFMActionTitle,
                    action: { model.openSettings(.lastFM) }
                )
            }

            AuraSection(title: "Get help") {
                RowGroup {
                    SupportRow(
                        symbol: "lifepreserver",
                        title: "Support report",
                        detail: model.diagnosticCopyStatus.isEmpty
                            ? "A privacy-safe summary to include when asking for help. Leaves out credentials, usernames, and listening details."
                            : model.diagnosticCopyStatus
                    ) {
                        Button("Copy Report", systemImage: "doc.on.doc") { model.copyDiagnosticReport() }
                            .auraButton(prominent: true)
                    }
                    RowDivider()
                    SupportRow(
                        symbol: "checkmark.seal",
                        title: "Verification snapshot",
                        detail: model.verificationExportStatus.isEmpty
                            ? "App and connection health without track metadata, usernames, credentials, or file paths."
                            : model.verificationExportStatus
                    ) {
                        HStack(spacing: BrandSpacing.xs) {
                            Button("Copy", systemImage: "doc.on.doc", action: model.copyVerificationReport)
                            Button("Save…", systemImage: "square.and.arrow.down", action: model.saveVerificationReport)
                        }
                        .auraButton()
                    }
                }
            }

            AuraSection(title: "Technical details", detail: "Performance, diagnostic messages, and connection history.") {
                Button(showsTechnicalDetails ? "Hide" : "Show") {
                    withAnimation(.easeInOut(duration: 0.2)) { showsTechnicalDetails.toggle() }
                }
                .buttonStyle(.link)
            } content: {
                if showsTechnicalDetails {
                    technicalDetails
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
        }
        .task {
            let metrics = await model.artworkCacheMetrics()
            artworkCacheSummary = "\(metrics.memoryEntries) in memory · \(metrics.diskEntries) on disk"
        }
    }

    private var technicalDetails: some View {
        VStack(alignment: .leading, spacing: BrandMetrics.gridSpacing) {
            RowGroup {
                DetailRow("macOS", ProcessInfo.processInfo.operatingSystemVersionString)
                RowDivider(inset: 0)
                DetailRow("Aura", "\(ReleaseConfiguration.version) (\(ReleaseConfiguration.build))")
                RowDivider(inset: 0)
                HStack {
                    DetailRow("Artwork cache", artworkCacheSummary)
                    if model.snapshot.track != nil, model.artworkImage == nil {
                        Button("Retry Artwork", systemImage: "arrow.clockwise") { model.retryCurrentArtwork() }
                            .buttonStyle(.borderless)
                    }
                }
                RowDivider(inset: 0)
                DetailRow(
                    "Latest playback check",
                    model.playbackPollMetrics.totalDuration.formatted(.number.precision(.fractionLength(1...1))) + " s"
                )
                ForEach(PlaybackProviderID.allCases) { provider in
                    if let duration = model.playbackPollMetrics.providerDurations[provider] {
                        RowDivider(inset: 0)
                        DetailRow(provider.displayName, "\(Int((duration * 1_000).rounded())) ms")
                    }
                }
            }

            AuraSection(title: "Recent diagnostic messages") {
                RowGroup {
                    if records.isEmpty {
                        Text("No diagnostic messages recorded.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .padding(.vertical, BrandSpacing.sm)
                    } else {
                        ForEach(Array(records.prefix(12).enumerated()), id: \.element.id) { index, record in
                            if index > 0 { RowDivider(inset: 0) }
                            HStack(alignment: .firstTextBaseline, spacing: BrandSpacing.sm) {
                                Text(record.category)
                                    .font(BrandTypography.mono.weight(.semibold))
                                    .foregroundStyle(.secondary)
                                    .frame(width: 90, alignment: .leading)
                                Text(record.message)
                                    .font(BrandTypography.mono)
                                    .textSelection(.enabled)
                                    .fixedSize(horizontal: false, vertical: true)
                                Spacer(minLength: 0)
                            }
                            .padding(.vertical, BrandSpacing.xs)
                        }
                    }
                }
            }

            AuraSection(title: "Recent connection changes") {
                RowGroup {
                    if healthEvents.isEmpty {
                        Text("No connection changes recorded.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .padding(.vertical, BrandSpacing.sm)
                    } else {
                        ForEach(Array(healthEvents.prefix(12).enumerated()), id: \.element.id) { index, event in
                            if index > 0 { RowDivider(inset: 0) }
                            HStack {
                                Text(IntegrationID(rawValue: event.integrationRaw)?.displayName ?? "Integration")
                                    .font(.callout.weight(.medium))
                                Spacer()
                                Text(IntegrationState(rawValue: event.stateRaw)?.rawValue.capitalized ?? event.stateRaw.capitalized)
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.secondary)
                                Text(event.timestamp, style: .relative)
                                    .font(.caption.monospacedDigit())
                                    .foregroundStyle(.tertiary)
                                    .frame(width: 110, alignment: .trailing)
                            }
                            .padding(.vertical, BrandSpacing.xs)
                        }
                    }
                }
            }
        }
    }

    private func lastConnected(_ id: IntegrationID) -> Date? {
        model.integrationHealth.first(where: { $0.integration == id })?.lastSuccessfulAt
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
}

private struct ConnectionStatusCard: View {
    let title: String
    let role: String
    let symbol: String
    let status: ServiceStatus
    let lastConnected: Date?
    let actionTitle: String?
    let action: () -> Void
    @Environment(\.appTheme) private var theme
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: BrandMetrics.cardContentSpacing) {
            HStack(spacing: BrandSpacing.sm) {
                SymbolTile(symbol: symbol, tint: theme.readablePrimary(for: colorScheme), size: BrandMetrics.tileLarge)
                VStack(alignment: .leading, spacing: 1) {
                    Text(title).font(.headline).lineLimit(1)
                    Text(role).font(.caption).foregroundStyle(.secondary)
                }
            }
            HStack(spacing: BrandSpacing.xs) {
                Image(systemName: status.symbol)
                    .foregroundStyle(status.tintColor)
                    .accessibilityHidden(true)
                Text(status.presentationLabel)
                    .foregroundStyle(status.tintColor)
            }
            .font(.callout.weight(.semibold))
            if let detail = status.detailLabel {
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
            } else if let lastConnected {
                Text("Last connected \(lastConnected.formatted(.relative(presentation: .named)))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            if let actionTitle {
                Button(actionTitle, action: action)
                    .auraButton(prominent: true)
                    .controlSize(.small)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 124, alignment: .topLeading)
        .padding(BrandMetrics.cardPadding)
        .auraSurface(status.isActionable ? .raised : .plain)
        .accessibilityElement(children: .contain)
    }
}

private struct SupportRow<Actions: View>: View {
    let symbol: String
    let title: String
    let detail: String
    @ViewBuilder var actions: Actions
    @Environment(\.appTheme) private var theme
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(spacing: BrandMetrics.cardContentSpacing) {
            SymbolTile(symbol: symbol, tint: theme.readablePrimary(for: colorScheme))
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.callout.weight(.semibold))
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: BrandSpacing.md)
            actions
        }
        .padding(.vertical, BrandSpacing.sm)
    }
}

private struct DetailRow: View {
    let label: String
    let value: String

    init(_ label: String, _ value: String) {
        self.label = label
        self.value = value
    }

    var body: some View {
        HStack {
            Text(label).font(.callout)
            Spacer()
            Text(value)
                .font(.callout.monospacedDigit())
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
        }
        .padding(.vertical, BrandSpacing.sm)
    }
}
