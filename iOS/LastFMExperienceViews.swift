import AuraCore
import Charts
import SwiftUI

private enum CompanionMainTab: Hashable {
    case scrobbles
    case reports
    case charts
}

struct LastFMAppShell: View {
    let model: CompanionAppModel
    @State private var selectedTab: CompanionMainTab = .scrobbles
    // Lets device smoke tests execute the same Scan flow without relying on
    // remote touch injection. Normal launches do not include this argument.
    @State private var isPresentingScan = ProcessInfo.processInfo.arguments.contains("-AuraStartScan")

    var body: some View {
        ZStack {
            CompanionBrand.canvas.ignoresSafeArea()
            TabView(selection: $selectedTab) {
                NavigationStack {
                    LastFMScrobblesScreen(model: model) { isPresentingScan = true }
                }
                .tag(CompanionMainTab.scrobbles)
                NavigationStack { LastFMReportsScreen(model: model) }
                    .tag(CompanionMainTab.reports)
                NavigationStack { LastFMChartsScreen(model: model) }
                    .tag(CompanionMainTab.charts)
            }
            .toolbar(.hidden, for: .tabBar)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            LastFMTabBar(selection: $selectedTab)
        }
        .fullScreenCover(isPresented: $isPresentingScan) {
            LastFMScanReviewScreen(model: model)
        }
    }
}

private struct LastFMTabBar: View {
    @Binding var selection: CompanionMainTab

    var body: some View {
        HStack(spacing: 0) {
            tabButton(.scrobbles, title: "Scrobbles", symbol: "music.note.list")
            tabButton(.reports, title: "Reports", symbol: "chart.pie.fill")
            tabButton(.charts, title: "Charts", symbol: "list.number")
        }
        .padding(5)
        .frame(maxWidth: 310)
        .background(.ultraThinMaterial, in: Capsule())

        .shadow(color: .black.opacity(0.35), radius: 18, y: 8)
        .padding(.horizontal, 24)
        .padding(.top, 8)
        .padding(.bottom, 4)
        .frame(maxWidth: .infinity)
        .background(
            LinearGradient(
                colors: [CompanionBrand.canvas.opacity(0), CompanionBrand.canvas.opacity(0.92)],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
        )
    }

    private func tabButton(_ tab: CompanionMainTab, title: String, symbol: String) -> some View {
        Button {
            selection = tab
        } label: {
            VStack(spacing: 2) {
                Image(systemName: symbol)
                    .font(.system(size: 18, weight: .semibold))
                Text(title)
                    .font(.caption2.weight(.medium))
            }
            .foregroundStyle(selection == tab ? CompanionBrand.scrobbleRed : Color.white.opacity(0.8))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
            .background(selection == tab ? Color.black.opacity(0.4) : Color.clear, in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selection == tab ? .isSelected : [])
    }
}

private struct LastFMScrobblesScreen: View {
    let model: CompanionAppModel
    let scan: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            LastFMHeader(model: model, scan: scan)
            if model.isLoadingLastFMHistory && model.lastFMTracks.isEmpty {
                Spacer()
                ProgressView("Loading scrobbles…")
                    .tint(.white)
                    .foregroundStyle(CompanionBrand.secondaryText)
                Spacer()
            } else if model.lastFMTracks.isEmpty {
                Spacer()
                ContentUnavailableView(
                    "No scrobbles yet",
                    systemImage: "music.note.list",
                    description: Text("Scan recent Apple Music plays or pull down to refresh Last.fm.")
                )
                Button("Refresh scrobbles") { Task { await model.refreshLastFMHistory() } }
                    .buttonStyle(.bordered)
                Spacer()
            } else {
                List(model.lastFMTracks) { track in
                    LastFMCompactTrackRow(track: track)
                        .listRowInsets(EdgeInsets(top: 7, leading: 12, bottom: 7, trailing: 12))
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .refreshable { await model.refreshLastFMHistory() }
            }
        }
        .background(CompanionBrand.canvas.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
    }
}

private struct LastFMHeader: View {
    let model: CompanionAppModel
    let scan: () -> Void

    var body: some View {
        HStack {
            Button(action: scan) {
                Text("Scan")
                    .font(.subheadline.weight(.semibold))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 9)
                    .background(Color.white.opacity(0.16), in: Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityHint("Find recent Apple Music plays to submit")

            Spacer()

            NavigationLink {
                CompanionSettingsView(model: model)
            } label: {
                ZStack {
                    Circle().fill(CompanionBrand.surface)
                    Text(profileInitial)
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(.white)
                }
                .frame(width: 39, height: 39)
                .overlay(Circle().strokeBorder(Color.white.opacity(0.14)))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Account and settings")
        }
        .overlay { Text("Scrobbles").font(.headline.weight(.bold)).allowsHitTesting(false) }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(CompanionBrand.surface)
    }

    private var profileInitial: String {
        model.lastFMUsername?.first.map { String($0).uppercased() } ?? "P"
    }
}

private struct LastFMCompactTrackRow: View {
    let track: CompanionLastFMTrack

    var body: some View {
        HStack(spacing: 11) {
            LastFMArtwork(url: track.artworkURL)
                .frame(width: 48, height: 48)
            VStack(alignment: .leading, spacing: 3) {
                Text(track.title)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                Text(track.artist)
                    .font(.caption)
                    .foregroundStyle(CompanionBrand.secondaryText)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            if track.isNowPlaying {
                Image(systemName: "waveform")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(CompanionBrand.scrobbleRed)
                    .accessibilityLabel("Now playing")
            } else if let date = track.playedAt {
                TimelineView(.periodic(from: .now, by: 60)) { context in
                    Text(lastFMRelativeText(date, now: context.date))
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(CompanionBrand.secondaryText)
                        .lineLimit(1)
                }
            }
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

private struct LastFMArtwork: View {
    let url: URL?

    var body: some View {
        AsyncImage(url: url) { phase in
            if let image = phase.image {
                image.resizable().scaledToFill()
            } else {
                CompanionBrand.surface
                    .overlay {
                        Image(systemName: "music.note")
                            .foregroundStyle(Color.white.opacity(0.45))
                    }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
        .accessibilityHidden(true)
    }
}

private struct LastFMScanReviewScreen: View {
    let model: CompanionAppModel
    @Environment(\.dismiss) private var dismiss
    @State private var selectedIDs = Set<String>()
    @State private var didSeedSelection = false
    @State private var isSubmitting = false
    @State private var isEditing = false
    @State private var editingListen: CanonicalListen?

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                scanHeader.disabled(isSubmitting)
                if model.isImportingAppleMusicHistory {
                    Spacer()
                    ProgressView("Scanning for new scrobbles…")
                        .tint(.white)
                    Spacer()
                } else if groups.isEmpty {
                    Spacer()
                    ContentUnavailableView(
                        "No new scrobbles",
                        systemImage: "checkmark.circle",
                        description: Text("Apple Music did not expose any unsubmitted recent plays.")
                    )
                    Button("Scan again") { Task { await scan() } }
                        .buttonStyle(.bordered)
                    Spacer()
                } else {
                    List(groups) { group in
                        Button {
                            if isEditing { toggle(group) }
                        } label: {
                            ScanCandidateRow(
                                group: group,
                                artworkURL: artworkURL(for: group),
                                isSelected: group.ids.allSatisfy(selectedIDs.contains),
                                showsSelection: isEditing
                            )
                        }
                        .buttonStyle(.plain)
                        .listRowInsets(EdgeInsets(top: 6, leading: 20, bottom: 6, trailing: 20))
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                        .swipeActions {
                            if let listen = group.listens.first {
                                Button("Edit", systemImage: "pencil") { editingListen = listen }
                                    .tint(.gray)
                            }
                        }
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                    .disabled(isSubmitting)
                }
            }
            .background(Color(white: 0.16).ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
            .safeAreaInset(edge: .bottom) {
                if !groups.isEmpty {
                    Button {
                        isSubmitting = true
                        Task {
                            await model.approveHistoricalImports(ids: selectedIDs)
                            isSubmitting = false
                            if model.historicalImportItems.isEmpty { dismiss() }
                        }
                    } label: {
                        Group {
                            if isSubmitting {
                                ProgressView().tint(.white)
                            } else {
                                Text(submitTitle).fontWeight(.bold)
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                    }
                    .buttonStyle(.plain)
                    .background(CompanionBrand.scrobbleRed, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                    .disabled(selectedIDs.isEmpty || isSubmitting)
                    .opacity(selectedIDs.isEmpty ? 0.45 : 1)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
                    .background(.ultraThinMaterial)
                }
            }
            .task { await scan() }
            .onChange(of: model.historicalImportItems.map(\.id)) { _, ids in
                guard !didSeedSelection, !ids.isEmpty else { return }
                selectedIDs = Set(ids)
                didSeedSelection = true
            }
        }
        .preferredColorScheme(.dark)
        .sheet(item: $editingListen) {
            MetadataEditor(model: model, listen: $0)
        }
    }

    private var scanHeader: some View {
        HStack {
            Button("Discard") { dismiss() }
                .font(.subheadline.weight(.semibold))
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .background(Color.white.opacity(0.15), in: Capsule())
            Spacer()
            Text(model.isImportingAppleMusicHistory ? "Scanning" : "\(selectedIDs.count) Scrobbles")
                .font(.headline.weight(.bold))
            Spacer()
            Button(isEditing ? "Done" : "Edit") { isEditing.toggle() }
                .font(.subheadline.weight(.semibold))
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .background(Color.white.opacity(0.15), in: Capsule())
                .disabled(groups.isEmpty)
        }
        .tint(.white)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(CompanionBrand.surface)
    }

    private var submitTitle: String {
        selectedIDs.count == groups.flatMap(\.ids).count ? "Submit all" : "Submit \(selectedIDs.count)"
    }

    private var groups: [ScanCandidateGroup] {
        Dictionary(grouping: model.historicalImportItems) { listen in
            "\(listen.canonicalMetadata.artist.lowercased())|\(listen.canonicalMetadata.title.lowercased())"
        }
        .values
        .map(ScanCandidateGroup.init)
        .sorted { ($0.startedAt ?? .distantPast) > ($1.startedAt ?? .distantPast) }
    }

    private func artworkURL(for group: ScanCandidateGroup) -> URL? {
        model.lastFMTracks.first {
            $0.title.localizedCaseInsensitiveCompare(group.title) == .orderedSame
                && $0.artist.localizedCaseInsensitiveCompare(group.artist) == .orderedSame
        }?.artworkURL
    }

    private func scan() async {
        didSeedSelection = false
        await model.importAvailableAppleMusicHistory()
        selectedIDs = Set(model.historicalImportItems.map(\.id))
        didSeedSelection = true
    }

    private func toggle(_ group: ScanCandidateGroup) {
        let ids = Set(group.ids)
        if ids.isSubset(of: selectedIDs) {
            selectedIDs.subtract(ids)
        } else {
            selectedIDs.formUnion(ids)
        }
    }
}

private struct ScanCandidateGroup: Identifiable {
    let listens: [CanonicalListen]
    var id: String { listens.first?.id ?? UUID().uuidString }
    var ids: [String] { listens.map(\.id) }
    var title: String { listens.first?.canonicalMetadata.title ?? "Unknown track" }
    var artist: String { listens.first?.canonicalMetadata.artist ?? "Unknown artist" }
    var album: String? { listens.first?.canonicalMetadata.album }
    var startedAt: Date? { listens.compactMap(\.canonicalMetadata.startedAt).max() }
}

private struct ScanCandidateRow: View {
    let group: ScanCandidateGroup
    let artworkURL: URL?
    let isSelected: Bool
    let showsSelection: Bool

    var body: some View {
        HStack(spacing: 11) {
            if showsSelection {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isSelected ? CompanionBrand.scrobbleRed : CompanionBrand.secondaryText)
            }
            LastFMArtwork(url: artworkURL).frame(width: 48, height: 48)
            VStack(alignment: .leading, spacing: 3) {
                Text(group.title).font(.subheadline.weight(.semibold)).lineLimit(1)
                Text(group.artist).font(.caption).foregroundStyle(CompanionBrand.secondaryText).lineLimit(1)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 4) {
                if let date = group.startedAt {
                    Text(lastFMRelativeText(date))
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(CompanionBrand.secondaryText)
                }
                if group.ids.count > 1 {
                    Text("×\(group.ids.count)")
                        .font(.caption.weight(.semibold).monospacedDigit())
                }
            }
        }
        .contentShape(Rectangle())
    }
}

// Report periods follow Last.fm: Friday–Thursday weeks and completed calendar months/years.
enum ListeningRange: String, CaseIterable, Identifiable {
    case week = "Last.week"
    case month = "Last.month"
    case year = "Last.year"

    var id: Self { self }

    func interval(offset: Int = 0, now: Date = .now, calendar: Calendar = .current) -> DateInterval {
        let component: Calendar.Component = self == .month ? .month : .year
        let end: Date
        if self == .week {
            let today = calendar.startOfDay(for: now)
            let daysSinceFriday = (calendar.component(.weekday, from: today) + 1) % 7
            end = calendar.date(byAdding: .day, value: -daysSinceFriday + offset * 7, to: today)!
            return DateInterval(start: calendar.date(byAdding: .day, value: -7, to: end)!, end: end)
        }
        let boundary = calendar.dateInterval(of: component, for: now)!.start
        end = calendar.date(byAdding: component, value: offset, to: boundary)!
        return DateInterval(start: calendar.date(byAdding: component, value: -1, to: end)!, end: end)
    }
}

private struct LastFMReportsScreen: View {
    let model: CompanionAppModel
    @State private var range: ListeningRange = .week
    @State private var offset = 0

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 20) {
                Text("Reports").font(.headline.bold()).padding(.top, 14)
                Picker("Report period", selection: $range) {
                    ForEach(ListeningRange.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                HStack {
                    Button {
                        offset -= 1
                    } label: {
                        Image(systemName: "chevron.left").frame(width: 44, height: 32)
                    }
                    .accessibilityLabel("Previous report")
                    Spacer()
                    Text(reportDates).font(.subheadline.weight(.semibold))
                    Spacer()
                    Button {
                        offset += 1
                    } label: {
                        Image(systemName: "chevron.right").frame(width: 44, height: 32)
                    }
                    .disabled(offset == 0)
                    .accessibilityLabel("Next report")
                }
                .tint(.primary)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 12)
            .background(CompanionBrand.surface)

            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    if tracks.isEmpty {
                        ContentUnavailableView(
                            "No scrobbles in this report", systemImage: "chart.bar.xaxis",
                            description: Text("Choose another period or refresh your listening history."))
                    } else {
                        VStack(alignment: .leading, spacing: 5) {
                            Text("\(tracks.count.formatted()) Scrobbles").font(.title2.bold())
                            Text("vs. \(previousTracks.count.formatted()) in the previous period")
                                .font(.subheadline).foregroundStyle(CompanionBrand.secondaryText)
                        }
                        comparisonChart
                        HStack(spacing: 24) {
                            legend("This period", color: CompanionBrand.scrobbleRed)
                            legend("Previous period", color: CompanionBrand.scrobbleRed.opacity(0.3))
                        }
                        HStack {
                            metric("Artists", value: ListeningSummary.entries(for: .artists, tracks: tracks).count)
                            metric("Albums", value: ListeningSummary.entries(for: .albums, tracks: tracks).count)
                            metric("Tracks", value: ListeningSummary.entries(for: .tracks, tracks: tracks).count)
                        }
                        ForEach(ChartKind.allCases) { kind in
                            if let entry = ListeningSummary.entries(for: kind, tracks: tracks).first {
                                NavigationLink {
                                    LastFMRankingScreen(kind: kind, tracks: tracks)
                                } label: {
                                    HStack(spacing: 14) {
                                        LastFMArtwork(url: entry.artworkURL).frame(width: 72, height: 72)
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text(kind.leaderTitle).font(.caption).foregroundStyle(CompanionBrand.secondaryText)
                                            Text(entry.name).font(.headline).lineLimit(2)
                                            Text(scrobbleCountText(entry.count)).font(.caption).foregroundStyle(CompanionBrand.secondaryText)
                                        }
                                        Spacer()
                                        Image(systemName: "chevron.right").foregroundStyle(CompanionBrand.secondaryText)
                                    }
                                }.buttonStyle(.plain)
                            }
                        }
                    }
                    historyCoverageNote
                }
                .padding(16)
                .padding(.top, 12)
            }
            .refreshable { await model.refreshLastFMHistory() }
        }
        .background(CompanionBrand.canvas.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .onChange(of: range) { _, _ in offset = 0 }
    }

    private var interval: DateInterval { range.interval(offset: offset) }
    private var tracks: [CompanionLastFMTrack] { ListeningSummary.tracks(model.lastFMTracks, in: interval) }
    private var previousTracks: [CompanionLastFMTrack] {
        ListeningSummary.tracks(model.lastFMTracks, in: range.interval(offset: offset - 1))
    }
    private var reportDates: String {
        let end = Calendar.current.date(byAdding: .day, value: -1, to: interval.end)!
        return "\(interval.start.formatted(.dateTime.day().month(.abbreviated))) – \(end.formatted(.dateTime.day().month(.abbreviated).year()))"
    }
    private var historyCoverageNote: some View {
        Text("Based on loaded Last.fm history (up to 2,000 scrobbles). Older periods may be incomplete.")
            .font(.caption).foregroundStyle(CompanionBrand.secondaryText)
    }
    private func metric(_ title: String, value: Int) -> some View {
        VStack(spacing: 4) {
            Text(value.formatted()).font(.title2.bold())
            Text(title).font(.caption).foregroundStyle(CompanionBrand.secondaryText)
        }.frame(maxWidth: .infinity)
    }
    private func legend(_ title: String, color: Color) -> some View {
        HStack(spacing: 6) {
            Rectangle().fill(color).frame(width: 10, height: 10)
            Text(title).font(.caption)
        }
    }
    private var comparisonChart: some View {
        Chart(buckets) { bucket in
            BarMark(x: .value("Date", bucket.label), y: .value("Scrobbles", bucket.current))
                .foregroundStyle(CompanionBrand.scrobbleRed)
                .position(by: .value("Period", "This period"))
            BarMark(x: .value("Date", bucket.label), y: .value("Scrobbles", bucket.previous))
                .foregroundStyle(CompanionBrand.scrobbleRed.opacity(0.3))
                .position(by: .value("Period", "Previous period"))
        }
        .chartLegend(.hidden)
        .chartYAxis { AxisMarks(position: .trailing, values: .automatic(desiredCount: 3)) }
        .frame(height: 210)
    }
    private var buckets: [ReportBucket] {
        ListeningSummary.buckets(range: range, offset: offset, tracks: model.lastFMTracks)
    }
}

enum ChartKind: String, CaseIterable, Identifiable {
    case artists = "Artists"
    case albums = "Albums"
    case tracks = "Tracks"
    var id: Self { self }
    var leaderTitle: String {
        switch self {
        case .artists: "Top artist"
        case .albums: "Top album"
        case .tracks: "Top track"
        }
    }
}

struct ChartEntry: Identifiable {
    let id: String
    let name: String
    let artist: String?
    let artworkURL: URL?
    let count: Int
}

enum ChartRange: String, CaseIterable, Identifiable {
    case week = "Last 7 days"
    case month = "Last 30 days"
    case year = "Last 365 days"
    case all = "All time"
    var id: Self { self }
    var days: Int? {
        switch self {
        case .week: 7
        case .month: 30
        case .year: 365
        case .all: nil
        }
    }
}

private struct LastFMChartsScreen: View {
    let model: CompanionAppModel
    @State private var range: ChartRange = .week
    @State private var isSelectingRange = false

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Spacer()
                Button {
                    isSelectingRange = true
                } label: {
                    Image(systemName: "calendar")
                        .frame(width: 40, height: 40)
                        .background(Color.white.opacity(0.1), in: Circle())
                }.accessibilityLabel("Select chart time range")
            }
            .overlay {
                VStack(spacing: 2) {
                    Text("Charts").font(.headline.bold())
                    Text(range.rawValue).font(.caption2).foregroundStyle(CompanionBrand.secondaryText)
                }.allowsHitTesting(false)
            }
            .tint(.primary)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)

            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("\(filteredTracks.count.formatted()) scrobbles").font(.title2.bold())
                        Text("Your daily average for this period is \(dailyAverage).")
                            .font(.subheadline)
                    }.padding(.horizontal, 16)
                    if filteredTracks.isEmpty {
                        ContentUnavailableView(
                            "No chart data", systemImage: "chart.bar.xaxis",
                            description: Text("Choose another time range or refresh your scrobbles."))
                    } else {
                        ForEach(ChartKind.allCases) { kind in
                            chartSection(kind)
                        }
                    }
                    Text("Based on loaded Last.fm history (up to 2,000 scrobbles). Longer ranges may be incomplete.")
                        .font(.caption).foregroundStyle(CompanionBrand.secondaryText).padding(.horizontal, 16)
                }.padding(.vertical, 20)
            }
            .refreshable { await model.refreshLastFMHistory() }
        }
        .background(CompanionBrand.canvas.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .confirmationDialog("Select time range", isPresented: $isSelectingRange, titleVisibility: .visible) {
            ForEach(ChartRange.allCases) { item in
                Button(item.rawValue) { range = item }
            }
        }
    }

    private func chartSection(_ kind: ChartKind) -> some View {
        let entries = ListeningSummary.entries(for: kind, tracks: filteredTracks)
        return VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("\(entries.count.formatted()) \(kind.rawValue)").font(.title3.bold())
                Spacer()
                NavigationLink("See more") { LastFMRankingScreen(kind: kind, tracks: filteredTracks) }
                    .font(.subheadline).foregroundStyle(CompanionBrand.scrobbleRed)
                    .accessibilityLabel("See more \(kind.rawValue.lowercased())")
            }.padding(.horizontal, 16)
            ScrollView(.horizontal) {
                LazyHStack(alignment: .top, spacing: 16) {
                    ForEach(entries.prefix(10)) { entry in
                        NavigationLink {
                            LastFMChartDetailScreen(entry: entry, kind: kind, tracks: filteredTracks)
                        } label: {
                            VStack(alignment: kind == .artists ? .center : .leading, spacing: 5) {
                                LastFMArtwork(url: entry.artworkURL)
                                    .frame(width: 144, height: 144)
                                    .clipShape(RoundedRectangle(cornerRadius: kind == .artists ? 72 : 3))
                                    .padding(.bottom, 3)
                                Text(entry.name).font(.subheadline.bold()).lineLimit(1)
                                Text(scrobbleCountText(entry.count)).font(.caption).foregroundStyle(CompanionBrand.secondaryText)
                            }.frame(width: 144)
                        }.buttonStyle(.plain)
                    }
                }.padding(.horizontal, 16)
            }.scrollIndicators(.hidden)
        }
    }
    private var filteredTracks: [CompanionLastFMTrack] {
        let cutoff = range.days.flatMap { Calendar.current.date(byAdding: .day, value: -$0, to: .now) } ?? .distantPast
        return model.lastFMTracks.filter { !$0.isNowPlaying && ($0.playedAt.map { $0 >= cutoff && $0 <= .now } ?? false) }
    }
    private var dailyAverage: Int {
        let days = range.days ?? max(1, Calendar.current.dateComponents([.day], from: filteredTracks.compactMap(\.playedAt).min() ?? .now, to: .now).day ?? 1)
        return Int((Double(filteredTracks.count) / Double(days)).rounded())
    }
}

private struct LastFMRankingScreen: View {
    let kind: ChartKind
    let tracks: [CompanionLastFMTrack]

    var body: some View {
        List(Array(ListeningSummary.entries(for: kind, tracks: tracks).enumerated()), id: \.element.id) { index, entry in
            NavigationLink {
                LastFMChartDetailScreen(entry: entry, kind: kind, tracks: tracks)
            } label: {
                HStack(spacing: 12) {
                    Text("\(index + 1)").font(.subheadline.monospacedDigit())
                        .foregroundStyle(CompanionBrand.secondaryText).frame(width: 24)
                    LastFMArtwork(url: entry.artworkURL).frame(width: 48, height: 48)
                        .clipShape(RoundedRectangle(cornerRadius: kind == .artists ? 24 : 3))
                    VStack(alignment: .leading, spacing: 4) {
                        Text(entry.name).font(.subheadline.bold()).lineLimit(1)
                        if let artist = entry.artist { Text(artist).font(.caption).foregroundStyle(CompanionBrand.secondaryText).lineLimit(1) }
                        Text(scrobbleCountText(entry.count)).font(.caption).foregroundStyle(CompanionBrand.secondaryText)
                    }
                }
            }.listRowBackground(Color.clear).listRowSeparator(.hidden)
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(CompanionBrand.canvas)
        .navigationTitle(kind.rawValue)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
    }
}

private struct LastFMChartDetailScreen: View {
    let entry: ChartEntry
    let kind: ChartKind
    let tracks: [CompanionLastFMTrack]

    var body: some View {
        List {
            VStack(spacing: 10) {
                LastFMArtwork(url: entry.artworkURL).frame(width: 180, height: 180)
                    .clipShape(RoundedRectangle(cornerRadius: kind == .artists ? 90 : 3))
                Text(entry.name).font(.title2.bold())
                if let artist = entry.artist { Text(artist).foregroundStyle(CompanionBrand.secondaryText) }
                Text(scrobbleCountText(entry.count)).font(.subheadline).foregroundStyle(CompanionBrand.secondaryText)
            }.frame(maxWidth: .infinity).padding(.vertical).listRowBackground(Color.clear).listRowSeparator(.hidden)
            Section("Scrobbles in this period") {
                ForEach(tracks.filter { ListeningSummary.key(for: kind, track: $0) == entry.id }) { track in
                    LastFMCompactTrackRow(track: track)
                        .listRowBackground(Color.clear).listRowSeparator(.hidden)
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(CompanionBrand.canvas)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
    }
}

private func lastFMRelativeText(_ date: Date, now: Date = .now) -> String {
    let elapsed = max(0, Int(now.timeIntervalSince(date)))
    if elapsed < 60 { return "now" }
    let minutes = elapsed / 60
    if minutes < 60 { return "\(minutes) min\(minutes == 1 ? "" : "s") ago" }
    let hours = minutes / 60
    if hours < 24 { return "\(hours) hour\(hours == 1 ? "" : "s") ago" }
    let days = hours / 24
    if days < 7 { return "\(days) day\(days == 1 ? "" : "s") ago" }
    return date.formatted(.dateTime.day().month(.abbreviated))
}

private func scrobbleCountText(_ count: Int) -> String {
    "\(count.formatted()) \(count == 1 ? "scrobble" : "scrobbles")"
}
