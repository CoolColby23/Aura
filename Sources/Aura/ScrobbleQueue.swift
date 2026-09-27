import Foundation
import SwiftData

@MainActor
final class ScrobbleQueue {
    private let store: PersistenceStore
    private let client: any ScrobbleSubmitting
    private let clock: any AppClock
    private var processingTask: Task<Void, Never>?
    private var isProcessing = false
    var onStuck: ((String) -> Void)?
    var onCapacity: ((String) -> Void)?
    /// Reports the duplicate key of a record Last.fm accepted, so the model can
    /// move the matching recent session to its submitted state.
    var onSubmitted: ((String) -> Void)?

    init(store: PersistenceStore, client: any ScrobbleSubmitting, clock: any AppClock = SystemAppClock()) {
        self.store = store
        self.client = client
        self.clock = clock
    }

    convenience init(store: PersistenceStore, client: any ScrobbleSubmitting, now: @escaping @Sendable () -> Date) {
        self.init(store: store, client: client, clock: ClosureAppClock(now: now))
    }

    @discardableResult
    func enqueue(_ session: PlaybackSession) -> QueueAdmission {
        let admission = store.enqueue(session, now: clock.now)
        switch admission {
        case .accepted: Task { await process() }
        case .warning(let message):
            onCapacity?(message)
            Task { await process() }
        case .rejected(let message): onCapacity?(message)
        case .duplicate: break
        }
        return admission
    }

    func start() {
        guard processingTask == nil else { return }
        processingTask = Task {
            while !Task.isCancelled {
                await process()
                try? await clock.sleep(until: clock.now.addingTimeInterval(IntegrationPolicy.scrobbleWorkerInterval))
            }
        }
    }

    func stop() { processingTask?.cancel(); processingTask = nil }

    func retry(id: UUID) { if store.retryScrobble(id: id, now: clock.now) { Task { await process() } } }
    func remove(id: UUID) { store.removeScrobble(id: id) }

    @discardableResult
    func retryAll() -> Int {
        let count = store.retryAllScrobbles(now: clock.now)
        if count > 0 { Task { await process() } }
        return count
    }

    @discardableResult
    func removeAll(in state: QueueState) -> Int { store.removeScrobbles(in: state) }

    func correct(id: UUID, title: String, artist: String, album: String?) -> Bool {
        guard
            store.correctScrobble(
                id: id,
                title: title,
                artist: artist,
                album: album,
                now: clock.now
            )
        else { return false }
        Task { await process() }
        return true
    }

    func process() async {
        // enqueue(), the periodic worker, startup recovery, and manual retries can all
        // request processing at once. Main-actor methods are reentrant across awaits,
        // so explicitly keep a single queue drain in flight to avoid submitting the
        // same persisted record multiple times and tripping Last.fm's rate limit.
        guard !isProcessing else { return }
        isProcessing = true
        defer { isProcessing = false }

        // A successful row remains observable until the next drain so the UI can
        // render its terminal state before bounded cleanup removes it.
        store.deleteSubmittedScrobbles()
        let now = clock.now
        let descriptor = FetchDescriptor<ScrobbleRecord>(
            predicate: #Predicate { ($0.stateRaw == "pending" || $0.stateRaw == "retrying") && $0.nextAttemptAt <= now },
            sortBy: [SortDescriptor(\.startedAt)]
        )
        guard let records = try? store.context.fetch(descriptor) else { return }
        for record in records {
            record.state = .retrying
            do {
                try await client.scrobble(
                    title: record.title, artist: record.artist, album: record.album,
                    duration: record.duration, startedAt: record.startedAt)
                record.state = .submitted
                record.lastError = nil
                onSubmitted?(record.duplicateKey)
            } catch let error as LastFMError {
                record.attempts += 1
                record.lastError = error.localizedDescription
                switch error {
                case .rejected:
                    record.state = .permanentlyFailed
                    if record.attempts >= 3 { onStuck?(record.title) }
                case .api(let code, _) where Self.permanentLastFMCodes.contains(code):
                    record.state = .permanentlyFailed
                    if record.attempts >= 3 { onStuck?(record.title) }
                case .retryLater(_, let minimumDelay):
                    // A daily limit or future timestamp is expected to clear. Don't
                    // announce it as stuck while the scheduled wait is still running.
                    scheduleRetry(record, error: error, now: now, minimumDelay: minimumDelay, notifyIfStuck: false)
                default:
                    let rateLimitDelay: TimeInterval = if case .api(let code, _) = error, code == 29 { 60 } else { 0 }
                    scheduleRetry(record, error: error, now: now, minimumDelay: rateLimitDelay, notifyIfStuck: true)
                }
            } catch {
                record.attempts += 1
                record.lastError = Redactor.redact(error.localizedDescription)
                scheduleRetry(record, error: error, now: now, minimumDelay: 0, notifyIfStuck: true)
            }
            store.save()
        }
    }

    /// Last.fm API error codes that describe this account or request and will
    /// not succeed if the same play is submitted again unchanged.
    private static let permanentLastFMCodes: Set<Int> = [4, 6, 7, 8, 9, 10, 13, 14, 15, 26]

    private func scheduleRetry(
        _ record: ScrobbleRecord, error: any Error, now: Date, minimumDelay: TimeInterval, notifyIfStuck: Bool
    ) {
        record.state = .pending
        let backoff = ScrobbleRetryPolicy.shared.nextDelaySeconds(attempt: record.attempts)
        record.nextAttemptAt = now.addingTimeInterval(max(backoff, minimumDelay))
        guard ScrobbleRetryPolicy.shared.shouldRetry(error: error, attempt: record.attempts) else {
            record.state = .permanentlyFailed
            onStuck?(record.title)
            return
        }
        if notifyIfStuck, record.attempts >= 3 { onStuck?(record.title) }
    }

    func retryDate(attempts: Int, from date: Date) -> Date {
        let delay = min(IntegrationPolicy.scrobbleRetryMaximum, pow(2, Double(min(max(attempts, 1), 11))) * 5)
        return date.addingTimeInterval(delay)
    }

}
