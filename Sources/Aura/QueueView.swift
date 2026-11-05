import SwiftData
import SwiftUI

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
        // Read once per render: each of these filters the full query result.
        let queued = queuedRecords
        let visible = visibleRecords
        let blocked = queued.count { $0.state == .permanentlyFailed }
        let sharedError = blocked > 0 ? commonError(in: queued) : nil
        AuraPage(title: "Pending Plays", subtitle: subtitle(queued: queued, blocked: blocked)) {
            if !queued.isEmpty {
                Button("Retry All", systemImage: "arrow.clockwise") { confirmingRetryAll = true }
                    .auraButton()
            }
        } content: {
            if blocked > 0 {
                AuraCallout(
                    symbol: "exclamationmark.triangle.fill",
                    tint: BrandColors.warning,
                    title: "\(blocked) \(blocked == 1 ? "play needs" : "plays need") attention",
                    message: sharedError ?? "Correct the details and retry, or remove them."
                ) {
                    if filter != .blocked {
                        Button("Show") { filter = .blocked }
                            .auraButton()
                            .accessibilityLabel("Show the \(blocked) plays that need attention")
                    }
                    Button("Last.fm Settings") { model.openSettings(.lastFM) }
                        .auraButton()
                }
            }

            if queued.isEmpty {
                AuraEmptyState(
                    symbol: "checkmark",
                    title: "Everything is synced",
                    message: "If Last.fm is unavailable, finished plays wait here and retry automatically."
                )
                .padding(.top, BrandSpacing.xxl)
            } else if visible.isEmpty {
                AuraEmptyState(
                    symbol: "line.3.horizontal.decrease",
                    title: "No matching plays",
                    message: searchText.isEmpty
                        ? "None of the \(queued.count) pending plays are in “\(filter.rawValue)”."
                        : "No pending plays match “\(searchText)”."
                ) {
                    Button("Show All Pending Plays") {
                        filter = .all
                        searchText = ""
                    }
                    .auraButton()
                }
            } else {
                RowGroup {
                    ForEach(Array(visible.enumerated()), id: \.element.id) { index, record in
                        if index > 0 { RowDivider(inset: BrandMetrics.tileMedium + BrandMetrics.cardContentSpacing) }
                        QueueRow(
                            record: record,
                            showsInlineError: record.state != .permanentlyFailed || record.lastError != sharedError
                        ) {
                            queueActions(for: record)
                        }
                        .contextMenu { queueActions(for: record) }
                    }
                }
                .accessibilityIdentifier("queue.list")
            }
        }
        .searchable(text: $searchText, prompt: "Search title, artist, or album")
        .toolbar {
            ToolbarItemGroup {
                Picker("Show", selection: $filter) {
                    ForEach(QueueFilter.allCases) { option in
                        Text(option.rawValue).tag(option)
                    }
                }
                .pickerStyle(.segmented)
                .disabled(queued.isEmpty)
                Menu("More", systemImage: "ellipsis") {
                    Button("Retry All Now", systemImage: "arrow.clockwise") { confirmingRetryAll = true }
                        .disabled(queued.isEmpty)
                    Divider()
                    Button("Remove All That Need Attention…", systemImage: "trash", role: .destructive) {
                        confirmingRemoveBlocked = true
                    }
                    .disabled(blocked == 0)
                }
                .menuIndicator(.hidden)
            }
        }
        .confirmationDialog(
            "Retry every pending play now?",
            isPresented: $confirmingRetryAll,
            titleVisibility: .visible
        ) {
            Button("Retry \(queued.count) \(queued.count == 1 ? "Play" : "Plays")") {
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
            Button("Remove \(blocked) \(blocked == 1 ? "Play" : "Plays")", role: .destructive) {
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

    /// Says when the queue moves on its own, so the page never implies the
    /// person has to do something when Aura is already handling it.
    private func subtitle(queued: [ScrobbleRecord], blocked: Int) -> String {
        guard !queued.isEmpty else {
            return "Plays that couldn’t reach Last.fm wait here and retry on their own."
        }
        let waiting = "\(queued.count) \(queued.count == 1 ? "play is" : "plays are") waiting for Last.fm."
        if blocked > 0 {
            return "\(waiting) \(blocked) \(blocked == 1 ? "needs" : "need") a correction before \(blocked == 1 ? "it" : "they") can be submitted."
        }
        // Key on the scheduled attempt, not the state: a retryable failure stays
        // `.pending` with a future `nextAttemptAt`.
        let next =
            queued
            .filter { $0.state == .pending || $0.state == .retrying }
            .map(\.nextAttemptAt)
            .min()
        guard let next, next > .now else { return "\(waiting) Aura keeps retrying in the background." }
        return "\(waiting) Next attempt around \(next.formatted(date: .omitted, time: .shortened))."
    }

    private func commonError(in queued: [ScrobbleRecord]) -> String? {
        let errors = queued.compactMap(\.lastError)
        guard let first = errors.first, errors.count == queued.count, errors.allSatisfy({ $0 == first }) else { return nil }
        return first
    }

    @ViewBuilder
    private func queueActions(for record: ScrobbleRecord) -> some View {
        if record.state == .permanentlyFailed {
            Button("Edit and Retry…", systemImage: "pencil") { requestCorrection(of: record) }
            Button("Retry Without Changes", systemImage: "arrow.clockwise") { model.retryScrobble(id: record.id) }
        }
        Button("Remove…", systemImage: "trash", role: .destructive) { requestRemoval(of: record) }
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

private struct QueueRow<Actions: View>: View {
    let record: ScrobbleRecord
    let showsInlineError: Bool
    @ViewBuilder let actions: () -> Actions
    @Environment(\.appTheme) private var theme
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(spacing: BrandMetrics.cardContentSpacing) {
            SymbolTile(symbol: symbol, tint: tint, size: BrandMetrics.tileMedium)
            VStack(alignment: .leading, spacing: 1) {
                Text(record.title)
                    .font(.callout.weight(.semibold))
                    .lineLimit(1)
                Text(record.album.map { "\(record.artist) · \($0)" } ?? record.artist)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                if showsInlineError, let error = record.lastError {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(record.state == .permanentlyFailed ? BrandColors.error : .secondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 2)
                }
            }
            Spacer(minLength: BrandMetrics.cardContentSpacing)
            VStack(alignment: .trailing, spacing: BrandSpacing.xs) {
                StatusPill(title: record.stateRaw.queueDisplayName, tint: tint)
                Text(timingDetail)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.tertiary)
            }
            .frame(width: BrandMetrics.rowTrailingColumn, alignment: .trailing)
            Menu("Actions", systemImage: "ellipsis.circle", content: actions)
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .labelStyle(.iconOnly)
                .fixedSize()
                .foregroundStyle(.secondary)
                .accessibilityLabel("Actions for \(record.title)")
        }
        .padding(.vertical, BrandSpacing.sm)
        .contentShape(.rect)
    }

    private var timingDetail: String {
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
        case .pending: theme.readablePrimary(for: colorScheme)
        case .retrying: BrandColors.warning
        case .permanentlyFailed: BrandColors.error
        case .submitted: BrandColors.success
        }
    }
}

private extension String {
    var queueDisplayName: String {
        switch self {
        case "permanentlyFailed": "Needs attention"
        case "retrying": "Retrying"
        case "pending": "Waiting"
        default: capitalized
        }
    }
}
