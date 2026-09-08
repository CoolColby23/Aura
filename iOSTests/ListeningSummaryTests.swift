import Foundation
import XCTest

@testable import AuraiOS

final class ListeningSummaryTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }
    private func date(_ value: String) -> Date {
        ISO8601DateFormatter().date(from: value)!
    }
    private func track(
        _ title: String = "Song", artist: String = "Artist", album: String? = "Album",
        at: Date? = nil, nowPlaying: Bool = false
    ) -> CompanionLastFMTrack {
        .init(title: title, artist: artist, album: album, artworkURL: nil, playedAt: at, isNowPlaying: nowPlaying)
    }
    func testReportsUseCompletedFridayToThursdayWeeks() {
        let now = date("2026-09-04T12:00:00Z")
        let interval = ListeningRange.week.interval(now: now, calendar: calendar)
        XCTAssertEqual(interval.start, date("2026-08-28T00:00:00Z"))
        XCTAssertEqual(interval.end, date("2026-09-04T00:00:00Z"))
        XCTAssertEqual(ListeningRange.week.interval(offset: -1, now: now, calendar: calendar).end, interval.start)
    }
    func testReportsUseCompletedCalendarMonthsAndYears() {
        let now = date("2026-09-04T12:00:00Z")
        let month = ListeningRange.month.interval(now: now, calendar: calendar)
        XCTAssertEqual(month.start, date("2026-08-01T00:00:00Z"))
        XCTAssertEqual(month.end, date("2026-09-01T00:00:00Z"))
        let year = ListeningRange.year.interval(now: now, calendar: calendar)
        XCTAssertEqual(year.start, date("2025-01-01T00:00:00Z"))
        XCTAssertEqual(year.end, date("2026-01-01T00:00:00Z"))
    }
    func testReportBoundariesExcludeNowPlayingAndNextPeriod() {
        let interval = ListeningRange.week.interval(now: date("2026-09-04T12:00:00Z"), calendar: calendar)
        let plays = [track(at: interval.start), track(at: interval.end), track(nowPlaying: true), track()]
        XCTAssertEqual(ListeningSummary.tracks(plays, in: interval).count, 1)
    }
    func testChartsSeparateSameNamedAlbumsAndNormalizeArtistCase() {
        let plays = [track(artist: "One"), track(artist: "one"), track(artist: "Two"), track(album: " "), track(nowPlaying: true)]
        let entries = ListeningSummary.entries(for: .albums, tracks: plays)
        XCTAssertEqual(entries.count, 2)
        XCTAssertEqual(entries.first?.count, 2)
        XCTAssertEqual(entries.first?.artist, "One")
    }
    func testComparisonPreservesExtraDaysOfPreviousMonth() {
        let plays = [track(at: date("2026-07-31T12:00:00Z")), track(at: date("2026-08-30T12:00:00Z"))]
        let buckets = ListeningSummary.buckets(
            range: .month, offset: 0, tracks: plays,
            now: date("2026-09-04T12:00:00Z"), calendar: calendar)
        XCTAssertEqual(buckets.count, 31)
        XCTAssertEqual(buckets[29].current, 1)
        XCTAssertEqual(buckets[30].previous, 1)
        XCTAssertEqual(buckets.reduce(0) { $0 + $1.current + $1.previous }, 2)
    }
}
