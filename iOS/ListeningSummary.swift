import Foundation

struct ReportBucket: Identifiable {
    let id: Int
    let label: String
    let current: Int
    let previous: Int
}

enum ListeningSummary {
    static func key(for kind: ChartKind, track: CompanionLastFMTrack) -> String {
        // Length-prefix components so punctuation inside metadata cannot merge different releases.
        let artist = track.artist.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let name: String
        switch kind {
        case .artists: return artist
        case .albums: name = track.album ?? ""
        case .tracks: name = track.title
        }
        let normalized = name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return "\(artist.utf8.count):\(artist)\(normalized)"
    }

    static func entries(for kind: ChartKind, tracks: [CompanionLastFMTrack]) -> [ChartEntry] {
        let eligible = tracks.filter {
            !$0.isNowPlaying && (kind != .albums || !($0.album ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        return Dictionary(grouping: eligible, by: { key(for: kind, track: $0) }).compactMap { id, plays in
            guard let first = plays.first else { return nil }
            let name: String
            switch kind {
            case .artists: name = first.artist
            case .albums: name = first.album ?? ""
            case .tracks: name = first.title
            }
            return ChartEntry(
                id: id, name: name, artist: kind == .artists ? nil : first.artist,
                artworkURL: plays.compactMap(\.artworkURL).first, count: plays.count)
        }.sorted { $0.count == $1.count ? $0.id < $1.id : $0.count > $1.count }
    }

    static func tracks(_ tracks: [CompanionLastFMTrack], in interval: DateInterval) -> [CompanionLastFMTrack] {
        tracks.filter {
            guard !$0.isNowPlaying, let date = $0.playedAt else { return false }
            return date >= interval.start && date < interval.end
        }
    }

    static func buckets(
        range: ListeningRange, offset: Int, tracks: [CompanionLastFMTrack], now: Date = .now,
        calendar: Calendar = .current
    ) -> [ReportBucket] {
        let currentInterval = range.interval(offset: offset, now: now, calendar: calendar)
        let previousInterval = range.interval(offset: offset - 1, now: now, calendar: calendar)
        let component: Calendar.Component = range == .year ? .month : .day
        let currentCount = calendar.dateComponents([component], from: currentInterval.start, to: currentInterval.end).value(for: component) ?? 0
        let previousCount = calendar.dateComponents([component], from: previousInterval.start, to: previousInterval.end).value(for: component) ?? 0
        let currentTracks = self.tracks(tracks, in: currentInterval)
        let previousTracks = self.tracks(tracks, in: previousInterval)
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = range == .week ? "EEE" : (range == .year ? "MMM" : "d")
        func counts(_ plays: [CompanionLastFMTrack], start: Date) -> [Int: Int] {
            Dictionary(grouping: plays) { track in
                calendar.dateComponents([component], from: start, to: track.playedAt!).value(for: component) ?? 0
            }.mapValues(\.count)
        }
        let current = counts(currentTracks, start: currentInterval.start)
        let previous = counts(previousTracks, start: previousInterval.start)
        return (0..<max(currentCount, previousCount)).map { index in
            let date = calendar.date(byAdding: component, value: index, to: currentInterval.start)!
            let label = range == .month ? String(index + 1) : formatter.string(from: date)
            return ReportBucket(id: index, label: label, current: current[index] ?? 0, previous: previous[index] ?? 0)
        }
    }
}
