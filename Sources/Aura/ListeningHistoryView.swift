import AppKit
import Charts
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

struct ListeningHistoryView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.appTheme) private var theme
    @Environment(\.colorScheme) private var colorScheme
    @Query(sort: \ActivityRecord.startedAt, order: .reverse) private var records: [ActivityRecord]
    @State private var searchText = ""
    @State private var outcome: HistoryOutcomeFilter = .all
    @State private var period: HistoryPeriod = .month
    @State private var tab: HistoryTab = .overview
    @State private var includeLastFMInActivity = false
    @State private var showingClearConfirmation = false
    @State private var exportDocument: HistoryCSVDocument?
    @State private var showingExporter = false

    var body: some View {
        Group {
            if records.isEmpty && !hasLastFMConnection && tab != .lastFM {
                AuraEmptyState(
                    title: "No listening history yet",
                    message: "Play music in a supported app and your private listening history will appear here."
                ) {
                    if model.preferences.lastFMEnabled == false {
                        Button("Connect Last.fm for History from Every Device") {
                            model.openSettings(.lastFM)
                        }
                        .auraButton(prominent: true)
                    }
                }
                .frame(maxHeight: .infinity)
            } else {
                AuraPage(title: tab.pageTitle, subtitle: headerDetail) {
                    headerControls
                } content: {
                    switch tab {
                    case .overview:
                        overview
                    case .insights:
                        insights
                    case .activity:
                        if includeLastFMInActivity { lastFMRemoteSection }
                        historyList
                    case .lastFM:
                        lastFMRemoteSection
                    }
                }
            }
        }
        .searchable(text: $searchText, prompt: "Search title, artist, or album")
        .toolbar {
            ToolbarItem(placement: .principal) {
                Picker("History View", selection: $tab) {
                    ForEach(HistoryTab.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
                .accessibilityIdentifier("history.view-mode")
            }
            ToolbarItem {
                Menu("More", systemImage: "ellipsis") {
                    if tab == .lastFM || includeLastFMInActivity {
                        Button("Refresh Last.fm", systemImage: "arrow.clockwise") {
                            Task { await model.refreshLastFMRemoteHistory(force: true) }
                        }
                        .disabled(!hasLastFMConnection || model.lastFMRemoteTracksLoading)
                    }
                    Button("Export Visible History…", systemImage: "square.and.arrow.up") { exportVisibleHistory() }
                        .disabled(filteredRecords.isEmpty)
                    Divider()
                    Button("Clear Listening History…", systemImage: "trash", role: .destructive) { showingClearConfirmation = true }
                        .disabled(records.isEmpty)
                }
                .menuIndicator(.hidden)
            }
        }
        .confirmationDialog(
            "Clear all listening history?",
            isPresented: $showingClearConfirmation,
            titleVisibility: .visible
        ) {
            Button("Clear History", role: .destructive) { model.clearListeningHistory() }
        } message: {
            Text("This permanently removes local listening activity. It does not change Last.fm history.")
        }
        .fileExporter(
            isPresented: $showingExporter,
            document: exportDocument,
            contentType: .commaSeparatedText,
            defaultFilename: "Aura-History"
        ) { _ in exportDocument = nil }
        .task(id: tab == .lastFM || includeLastFMInActivity) {
            if tab == .lastFM || includeLastFMInActivity {
                await model.refreshLastFMRemoteHistory()
            }
        }
    }

    // MARK: Header

    @ViewBuilder
    private var headerControls: some View {
        switch tab {
        case .overview, .insights:
            periodPicker
        case .activity:
            HStack(spacing: BrandSpacing.sm) {
                Menu {
                    Picker("Outcome", selection: $outcome) {
                        ForEach(HistoryOutcomeFilter.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.inline)
                    Divider()
                    Toggle("Include Last.fm Scrobbles", isOn: $includeLastFMInActivity)
                } label: {
                    Label(outcome == .all ? "Filter" : outcome.rawValue, systemImage: "line.3.horizontal.decrease")
                }
                .menuStyle(.button)
                .auraButton()
                .fixedSize()
                periodPicker
            }
        case .lastFM:
            if model.lastFMRemoteTracksLoading {
                ProgressView().controlSize(.small)
            } else {
                Button("Refresh", systemImage: "arrow.clockwise") {
                    Task { await model.refreshLastFMRemoteHistory(force: true) }
                }
                .auraButton()
                .disabled(!hasLastFMConnection)
            }
        }
    }

    private var periodPicker: some View {
        Picker("Period", selection: $period) {
            ForEach(HistoryPeriod.allCases) { Text($0.rawValue).tag($0) }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .fixedSize()
    }

    private var headerDetail: String {
        switch tab {
        case .overview, .insights:
            return period == .all
                ? "Everything Aura has recorded on this Mac. It never leaves this Mac."
                : "The last \(period.rawValue.lowercased()) on this Mac. It never leaves this Mac."
        case .activity:
            return "Every play Aura recorded, newest first."
        case .lastFM:
            if model.lastFMUsername.isEmpty {
                return "Connect Last.fm to see scrobbles from your phone and other devices."
            }
            if let updated = model.lastFMRemoteTracksUpdatedAt {
                return "Recent scrobbles for \(model.lastFMUsername) from every device · Updated \(updated.formatted(date: .omitted, time: .shortened))"
            }
            return "Recent scrobbles for \(model.lastFMUsername), including other devices."
        }
    }

    private var hasLastFMConnection: Bool {
        model.preferences.lastFMEnabled && !model.lastFMUsername.isEmpty
    }

    // MARK: Overview

    @ViewBuilder
    private var overview: some View {
        let insights = extendedInsights
        let summary = self.summary
        StatBand(
            items: [
                .init(
                    label: "Listens", value: insights.comparison.current.listens.formatted(),
                    delta: comparison(insights.comparison.listenDelta)),
                .init(
                    label: "Minutes", value: insights.comparison.current.minutes.formatted(),
                    delta: comparison(insights.comparison.minuteDelta)),
                .init(
                    label: "Artists", value: insights.comparison.current.uniqueArtists.formatted(),
                    delta: comparison(insights.comparison.artistDelta)),
                .init(
                    label: "Early skips",
                    value: insights.comparison.current.skipRate.formatted(.percent.precision(.fractionLength(0))),
                    delta: nil,
                    help:
                        "The share of eligible tracks changed before they reached the Last.fm listening threshold. Pauses and interrupted sessions are excluded."
                ),
            ],
            footnote: periodComparisonDetail(insights)
        )

        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 340), spacing: BrandMetrics.gridSpacing, alignment: .top)],
            alignment: .leading,
            spacing: BrandMetrics.gridSpacing
        ) {
            ChartSurface(title: "Last 7 days", caption: "\(summary.dailyCounts.reduce(0) { $0 + $1.plays }) listens") {
                Chart(summary.dailyCounts) { item in
                    BarMark(x: .value("Day", item.day, unit: .day), y: .value("Listens", item.plays), width: .ratio(0.55))
                        .foregroundStyle(theme.primaryColor.gradient)
                        .clipShape(.rect(cornerRadius: 5, style: .continuous))
                }
                .chartXAxis {
                    AxisMarks(values: .stride(by: .day)) { _ in
                        AxisValueLabel(format: .dateTime.weekday(.abbreviated))
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .trailing, values: .automatic(desiredCount: 3)) {
                        AxisGridLine().foregroundStyle(BrandColors.hairline)
                        AxisValueLabel()
                    }
                }
                .frame(height: 180)
                .accessibilityLabel("Listens during the most recent seven days using the active filters")
            }
            ChartSurface(title: "Top artists", caption: "By listens") {
                if summary.topArtists.isEmpty {
                    Text("No played tracks in this period.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, minHeight: 180, alignment: .center)
                } else {
                    RankedList(
                        items: summary.topArtists.map { RankedListen(name: $0.artist, detail: nil, plays: $0.plays) },
                        showsBars: true
                    )
                }
            }
        }

        weeklyRecap
    }

    private var weeklyRecap: some View {
        let recap = WeeklyListeningRecap(records: records)
        return AuraSection(title: "This week", detail: "The last seven days, ready to share.") {
            Button("Copy Recap", systemImage: "doc.on.doc") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(recap.shareText, forType: .string)
            }
            .auraButton()
            .controlSize(.small)
            .disabled(recap.listens == 0)
        } content: {
            VStack(alignment: .leading, spacing: BrandSpacing.md) {
                if recap.listens == 0 {
                    Text("Your weekly recap appears after you finish a listen.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                } else {
                    Text(recapHeadline(recap))
                        .font(BrandTypography.cardTitle)
                        .fixedSize(horizontal: false, vertical: true)
                    LazyVGrid(
                        columns: [GridItem(.adaptive(minimum: 170), spacing: BrandSpacing.md, alignment: .topLeading)],
                        alignment: .leading,
                        spacing: BrandSpacing.md
                    ) {
                        if let value = recap.topTrack { RecapFact(label: "Top track", value: value) }
                        if let value = recap.topAlbum { RecapFact(label: "Top album", value: value) }
                        if let value = recap.topPlatform { RecapFact(label: "Mostly on", value: value) }
                        if let value = recap.busiestDay { RecapFact(label: "Busiest day", value: value) }
                    }
                }
            }
            .padding(BrandMetrics.cardPaddingSpacious)
            .frame(maxWidth: .infinity, alignment: .leading)
            .auraSurface(.raised)
            .accessibilityElement(children: .contain)
        }
    }

    private func recapHeadline(_ recap: WeeklyListeningRecap) -> String {
        var line = "\(recap.listens.formatted()) listens across \(recap.minutes.formatted()) minutes and \(recap.uniqueArtists.formatted()) artists."
        if let artist = recap.topArtist { line += " \(artist) led the week." }
        return line
    }

    // MARK: Insights

    @ViewBuilder
    private var insights: some View {
        let insights = extendedInsights
        LazyVGrid(columns: twoColumns, alignment: .leading, spacing: BrandMetrics.gridSpacing) {
            ChartSurface(title: "Top tracks") {
                if insights.topTracks.isEmpty {
                    emptyInsight
                } else {
                    RankedList(items: insights.topTracks)
                }
            }
            ChartSurface(title: "Top albums") {
                if insights.topAlbums.isEmpty {
                    emptyInsight
                } else {
                    RankedList(items: insights.topAlbums)
                }
            }
            ChartSurface(title: "Listening by hour", caption: peakHourCaption(insights)) {
                Chart(insights.hourlyCounts) { item in
                    BarMark(x: .value("Hour", item.hour), y: .value("Listens", item.plays))
                        .foregroundStyle(theme.primaryColor.gradient)
                        .clipShape(.rect(cornerRadius: 3, style: .continuous))
                }
                .chartXAxis {
                    AxisMarks(values: [0, 6, 12, 18, 23]) { value in
                        AxisValueLabel {
                            if let hour = value.as(Int.self) { Text(hourLabel(hour)) }
                        }
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .trailing, values: .automatic(desiredCount: 3)) {
                        AxisGridLine().foregroundStyle(BrandColors.hairline)
                        AxisValueLabel()
                    }
                }
                .frame(height: 150)
                .accessibilityLabel(hourlyAccessibilitySummary(insights))
            }
            ChartSurface(title: "Music apps") {
                if insights.platformCounts.isEmpty {
                    emptyInsight
                } else {
                    VStack(spacing: BrandSpacing.md) {
                        ForEach(insights.platformCounts) { item in
                            VStack(spacing: BrandSpacing.xs) {
                                HStack {
                                    Text(item.platform).font(.callout.weight(.medium))
                                    Spacer()
                                    Text(item.plays.formatted())
                                        .font(.callout.monospacedDigit())
                                        .foregroundStyle(.secondary)
                                }
                                AuraProgressBar(
                                    value: Double(item.plays),
                                    total: Double(max(insights.comparison.current.listens, 1))
                                )
                            }
                            .accessibilityElement(children: .combine)
                        }
                    }
                }
            }
        }
        Text(
            "Comparisons use the immediately preceding equal-length period and all available local history. Search does not change comparison values; retention settings may limit older data."
        )
        .font(.caption)
        .foregroundStyle(.secondary)
    }

    private var emptyInsight: some View {
        Text("No played tracks in this period.")
            .font(.callout)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, minHeight: 120, alignment: .center)
    }

    private var twoColumns: [GridItem] {
        [
            GridItem(.flexible(minimum: 260), spacing: BrandMetrics.gridSpacing, alignment: .top),
            GridItem(.flexible(minimum: 260), spacing: BrandMetrics.gridSpacing, alignment: .top),
        ]
    }

    private func hourLabel(_ hour: Int) -> String {
        var components = DateComponents()
        components.hour = hour
        let date = Calendar.current.date(from: components) ?? .now
        return date.formatted(.dateTime.hour())
    }

    private func peakHourCaption(_ insights: ExtendedListeningInsights) -> String? {
        guard let peak = insights.hourlyCounts.max(by: { $0.plays < $1.plays }), peak.plays > 0 else { return nil }
        return "Busiest around \(hourLabel(peak.hour))"
    }

    private func hourlyAccessibilitySummary(_ insights: ExtendedListeningInsights) -> String {
        guard let peak = insights.hourlyCounts.max(by: { $0.plays < $1.plays }), peak.plays > 0 else {
            return "No hourly listening activity in the selected period"
        }
        return "Hourly listening activity. The busiest hour begins at \(peak.hour):00 with \(peak.plays) listens."
    }

    // MARK: Activity

    @ViewBuilder
    private var historyList: some View {
        let visible = filteredRecords
        if visible.isEmpty {
            AuraEmptyState(
                symbol: "magnifyingglass",
                title: "No matches",
                message: "Adjust the search, the period, or the outcome filter."
            )
        } else {
            LazyVStack(alignment: .leading, spacing: BrandSpacing.lg) {
                ForEach(dayGroups(visible), id: \.day) { group in
                    VStack(alignment: .leading, spacing: BrandSpacing.sm) {
                        HStack(alignment: .firstTextBaseline) {
                            Text(dayTitle(group.day))
                                .font(BrandTypography.groupTitle)
                                .accessibilityAddTraits(.isHeader)
                            Spacer()
                            Text("\(group.records.count) \(group.records.count == 1 ? "play" : "plays")")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                        RowGroup {
                            ForEach(Array(group.records.enumerated()), id: \.element.id) { index, record in
                                if index > 0 { RowDivider(inset: BrandMetrics.rowArtwork + BrandMetrics.cardContentSpacing) }
                                HistoryRow(record: record, currentArtwork: isCurrent(record) ? model.artworkData : nil)
                            }
                        }
                    }
                }
            }
        }
    }

    private struct DayGroup {
        let day: Date
        var records: [ActivityRecord]
    }

    private func dayGroups(_ records: [ActivityRecord]) -> [DayGroup] {
        let calendar = Calendar.current
        var groups: [DayGroup] = []
        for record in records {
            let day = calendar.startOfDay(for: record.startedAt)
            if groups.last?.day == day {
                groups[groups.count - 1].records.append(record)
            } else {
                groups.append(DayGroup(day: day, records: [record]))
            }
        }
        return groups
    }

    private func dayTitle(_ day: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(day) { return "Today" }
        if calendar.isDateInYesterday(day) { return "Yesterday" }
        if let days = calendar.dateComponents([.day], from: day, to: calendar.startOfDay(for: .now)).day, days < 7 {
            return day.formatted(.dateTime.weekday(.wide))
        }
        return day.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())
    }

    // MARK: Last.fm

    private var lastFMRemoteSection: some View {
        let tracks = filteredRemoteTracks
        return AuraSection(
            title: tab == .lastFM ? "Recent scrobbles" : "From Last.fm",
            detail: "Includes listens recorded outside Aura."
        ) {
            if !hasLastFMConnection {
                AuraEmptyState(
                    symbol: "person.crop.circle.badge.questionmark",
                    title: "Last.fm isn’t connected",
                    message: "Authorize Last.fm to see scrobbles from your phone and other devices."
                ) {
                    Button("Open Last.fm Settings") { model.openSettings(.lastFM) }
                        .auraButton(prominent: true)
                }
                .auraSurface()
            } else if let error = model.lastFMRemoteTracksError, tracks.isEmpty {
                AuraEmptyState(symbol: "exclamationmark.triangle", title: "Couldn’t load Last.fm", message: error)
                    .auraSurface()
            } else if tracks.isEmpty {
                AuraEmptyState(
                    symbol: "magnifyingglass",
                    title: model.lastFMRemoteTracksLoading ? "Loading Last.fm…" : "No matching scrobbles",
                    message: searchText.isEmpty ? "Finished scrobbles from Last.fm will show here." : "Try a different search."
                )
                .auraSurface()
            } else {
                RowGroup {
                    ForEach(Array(tracks.enumerated()), id: \.element.id) { index, track in
                        if index > 0 { RowDivider(inset: BrandMetrics.rowArtwork + BrandMetrics.cardContentSpacing) }
                        LastFMRemoteHistoryRow(track: track)
                    }
                }
            }
        }
    }

    // MARK: Data

    private var summary: ListeningSummary { ListeningSummary(records: filteredRecords) }
    private var extendedInsights: ExtendedListeningInsights {
        ExtendedListeningInsights(records: records, period: period)
    }

    private func periodComparisonDetail(_ insights: ExtendedListeningInsights) -> String {
        if period == .all { return "Totals across all listening history on this Mac." }
        let comparisonPeriod = "\(period.dayCount ?? 0) days"
        if insights.comparison.listenDelta == nil {
            return "Comparisons appear once there is an earlier \(comparisonPeriod) of history."
        }
        return "Changes are against the previous \(comparisonPeriod)."
    }

    private func comparison(_ delta: Int?) -> StatBand.Delta? {
        guard period != .all, let delta else { return nil }
        return StatBand.Delta(value: delta)
    }

    private var filteredRecords: [ActivityRecord] {
        let cutoff = period.cutoff(from: .now)
        return records.filter { record in
            let matchesPeriod = cutoff.map { record.startedAt >= $0 } ?? true
            let matchesOutcome: Bool =
                switch outcome {
                case .all: true
                case .played: record.outcomeLabel == "Played"
                case .listened: record.outcomeLabel == "Listened"
                case .skipped: record.outcomeLabel == "Skipped"
                }
            let matchesSearch =
                searchText.isEmpty
                || [record.title, record.artist, record.album ?? ""]
                    .contains { $0.localizedCaseInsensitiveContains(searchText) }
            return matchesPeriod && matchesOutcome && matchesSearch
        }
    }

    private var filteredRemoteTracks: [LastFMRemoteTrack] {
        model.lastFMRemoteTracks.filter { track in
            searchText.isEmpty
                || [track.title, track.artist, track.album ?? ""]
                    .contains { $0.localizedCaseInsensitiveContains(searchText) }
        }
    }

    private func isCurrent(_ record: ActivityRecord) -> Bool {
        record.title == model.snapshot.track?.title && record.artist == model.snapshot.track?.artist
    }

    private func exportVisibleHistory() {
        exportDocument = HistoryCSVDocument(text: HistoryCSVExporter.csv(records: filteredRecords))
        showingExporter = true
    }
}

private enum HistoryTab: String, CaseIterable, Identifiable {
    case overview = "Overview"
    case insights = "Insights"
    case activity = "Activity"
    case lastFM = "Last.fm"

    var id: Self { self }

    var pageTitle: String {
        switch self {
        case .overview: "Your listening"
        case .insights: "Insights"
        case .activity: "Activity"
        case .lastFM: "Last.fm"
        }
    }
}

// MARK: - Components

/// The headline numbers for a period, set as one band rather than four boxes.
private struct StatBand: View {
    struct Delta {
        let value: Int
    }

    struct Item: Identifiable {
        let label: String
        let value: String
        let delta: Delta?
        var help: String?
        var id: String { label }
    }

    let items: [Item]
    let footnote: String

    var body: some View {
        VStack(alignment: .leading, spacing: BrandSpacing.md) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 0) {
                    ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                        if index > 0 {
                            Rectangle().fill(BrandColors.hairline).frame(width: 1, height: 56)
                        }
                        StatBlock(item: item)
                            .padding(.horizontal, BrandSpacing.lg)
                    }
                }
                Grid(alignment: .leading, horizontalSpacing: BrandSpacing.lg, verticalSpacing: BrandSpacing.lg) {
                    GridRow {
                        ForEach(items.prefix(2)) { StatBlock(item: $0) }
                    }
                    GridRow {
                        ForEach(items.dropFirst(2)) { StatBlock(item: $0) }
                    }
                }
                .padding(.horizontal, BrandSpacing.lg)
            }
            Text(footnote)
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, BrandSpacing.lg)
        }
        .padding(.vertical, BrandSpacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .auraSurface(.raised, radius: BrandRadius.lg)
    }
}

private struct StatBlock: View {
    let item: StatBand.Item
    @Environment(\.appTheme) private var theme
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: BrandSpacing.xs) {
            HStack(spacing: 4) {
                Text(item.label)
                    .auraEyebrow()
                    .foregroundStyle(.secondary)
                if item.help != nil {
                    Image(systemName: "info.circle")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .accessibilityHidden(true)
                }
            }
            Text(item.value)
                .font(BrandTypography.statValue)
                .monospacedDigit()
                .contentTransition(.numericText())
            Group {
                if let delta = item.delta {
                    Label(deltaText(delta.value), systemImage: deltaSymbol(delta.value))
                        .foregroundStyle(delta.value > 0 ? theme.readablePrimary(for: colorScheme) : Color.secondary)
                } else {
                    Text(" ")
                }
            }
            .font(.caption.weight(.semibold).monospacedDigit())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .help(item.help ?? "")
        .accessibilityElement(children: .combine)
        .accessibilityHint(item.help ?? "")
    }

    private func deltaText(_ value: Int) -> String {
        value == 0 ? "Same as before" : "\(abs(value).formatted()) \(value > 0 ? "more" : "fewer")"
    }

    private func deltaSymbol(_ value: Int) -> String {
        value == 0 ? "equal" : (value > 0 ? "arrow.up.right" : "arrow.down.right")
    }
}

private struct ChartSurface<Content: View>: View {
    let title: String
    var caption: String?
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: BrandSpacing.md) {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .font(BrandTypography.groupTitle)
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                if let caption {
                    Text(caption)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            content
        }
        .padding(BrandMetrics.cardPaddingSpacious - 4)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .auraSurface()
    }
}

private struct RankedList: View {
    let items: [RankedListen]
    var showsBars = false
    @Environment(\.appTheme) private var theme
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let top = Double(max(items.first?.plays ?? 1, 1))
        VStack(alignment: .leading, spacing: BrandSpacing.sm) {
            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                HStack(alignment: .center, spacing: BrandSpacing.sm) {
                    Text("\(index + 1)")
                        .font(.callout.weight(.bold).monospacedDigit())
                        .foregroundStyle(index == 0 ? theme.readablePrimary(for: colorScheme) : Color.secondary)
                        .frame(width: 22, alignment: .leading)
                    VStack(alignment: .leading, spacing: showsBars ? BrandSpacing.xs : 1) {
                        Text(item.name)
                            .font(.callout.weight(.medium))
                            .lineLimit(1)
                        if let detail = item.detail {
                            Text(detail)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        if showsBars {
                            AuraProgressBar(
                                value: Double(item.plays), total: top, height: 4,
                                tint: index == 0 ? theme.primaryColor : BrandColors.neutral.opacity(0.6))
                        }
                    }
                    Spacer(minLength: BrandSpacing.sm)
                    Text(item.plays.formatted())
                        .font(.callout.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .combine)
            }
        }
    }
}

private struct RecapFact: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .auraEyebrow()
                .foregroundStyle(.secondary)
            Text(value)
                .font(.callout.weight(.medium))
                .lineLimit(2)
        }
        .accessibilityElement(children: .combine)
    }
}

private struct HistoryRow: View {
    let record: ActivityRecord
    let currentArtwork: Data?

    var body: some View {
        HStack(spacing: BrandMetrics.cardContentSpacing) {
            ArtworkView(data: currentArtwork ?? record.artworkData, size: BrandMetrics.rowArtwork)
            VStack(alignment: .leading, spacing: 1) {
                Text(record.title)
                    .font(.callout.weight(.semibold))
                    .lineLimit(1)
                Text([record.artist, record.album].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · "))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: BrandSpacing.sm)
            OutcomeLabel(outcome: record.outcomeLabel)
            Text(record.startedAt, format: .dateTime.hour().minute())
                .font(.caption.monospacedDigit())
                .foregroundStyle(.tertiary)
                .frame(width: 64, alignment: .trailing)
        }
        .padding(.vertical, BrandSpacing.xs + 2)
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
    }
}

private struct LastFMRemoteHistoryRow: View {
    let track: LastFMRemoteTrack
    @Environment(\.appTheme) private var theme
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(spacing: BrandMetrics.cardContentSpacing) {
            remoteArtwork
            VStack(alignment: .leading, spacing: 1) {
                Text(track.title)
                    .font(.callout.weight(.semibold))
                    .lineLimit(1)
                Text([track.artist, track.album].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · "))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: BrandSpacing.sm)
            if track.isNowPlaying {
                StatusPill(title: "Now", symbol: nil, tint: BrandColors.blush)
            }
            Group {
                if let listenedAt = track.listenedAt {
                    Text(listenedAt, format: .dateTime.month(.abbreviated).day().hour().minute())
                } else if track.isNowPlaying {
                    Text("Playing")
                }
            }
            .font(.caption.monospacedDigit())
            .foregroundStyle(.tertiary)
            .frame(width: BrandMetrics.rowTrailingColumn, alignment: .trailing)
        }
        .padding(.vertical, BrandSpacing.xs + 2)
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var remoteArtwork: some View {
        let size = BrandMetrics.rowArtwork
        Group {
            if let url = track.imageURL {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image): image.resizable().scaledToFill()
                    default: remotePlaceholder
                    }
                }
            } else {
                remotePlaceholder
            }
        }
        .frame(width: size, height: size)
        .clipShape(.rect(cornerRadius: size * ArtworkView.cornerRatio, style: .continuous))
    }

    private var remotePlaceholder: some View {
        ZStack {
            theme.primaryColor.opacity(0.12)
            BrandMark().padding(BrandSpacing.sm)
        }
    }
}

private struct OutcomeLabel: View {
    let outcome: String
    @Environment(\.appTheme) private var theme
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        StatusPill(title: outcome, symbol: outcome == "Skipped" ? "forward.fill" : "checkmark", tint: tint)
    }

    private var tint: Color {
        outcome == "Skipped" ? BrandColors.neutral : theme.readablePrimary(for: colorScheme)
    }
}

struct HistoryCSVDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.commaSeparatedText] }
    let text: String

    init(text: String) { self.text = text }
    init(configuration: ReadConfiguration) throws {
        text = configuration.file.regularFileContents.flatMap { String(data: $0, encoding: .utf8) } ?? ""
    }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: Data(text.utf8))
    }
}
