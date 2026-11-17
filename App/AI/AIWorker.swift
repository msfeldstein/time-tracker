import Foundation
import Network
import Observation
import TimeTrackerCore

/// Runs all LLM work. The queue is the data itself (captures marked pending, uncategorized finished
/// activities, forgotten timers, summaries she has looked at), so nothing is lost if the app quits.
/// Offline or failing calls back off exponentially and retry when the network returns.
@MainActor
@Observable
final class AIWorker {
    static let shared = AIWorker()

    enum Status: Equatable {
        case off
        case idle
        case working
        case waiting(until: Date, reason: String)
        case needsAttention(String)
    }

    private(set) var status: Status = .off
    private(set) var lastSuccess: Date?

    @ObservationIgnored private var isRunning = false
    @ObservationIgnored private var runAgain = false
    @ObservationIgnored private var failures = 0
    @ObservationIgnored private var backoffUntil: Date?
    @ObservationIgnored private var retryTask: Task<Void, Never>?
    @ObservationIgnored private var tickTask: Task<Void, Never>?
    @ObservationIgnored private var monitor: NWPathMonitor?
    @ObservationIgnored private var attemptedSuggestions = Set<UUID>()
    @ObservationIgnored private var failedCategoryKeys = Set<String>()
    @ObservationIgnored private var wantedSummaries: [String: SummarySpec] = [:]

    struct SummarySpec: Equatable {
        let key: String
        let period: SummaryPeriod
        let interval: DateInterval
        let label: String
    }

    private var store: EntryService { EntryService.shared }

    // MARK: - Lifecycle

    func start() {
        guard monitor == nil else { return }
        store.onChange = { [weak self] in self?.kick() }

        let monitor = NWPathMonitor()
        monitor.pathUpdateHandler = { path in
            guard path.status == .satisfied else { return }
            Task { @MainActor in AIWorker.shared.networkCameBack() }
        }
        monitor.start(queue: DispatchQueue(label: "TimeTracker.AIWorker.network"))
        self.monitor = monitor

        tickTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(600))
                self?.kick()
            }
        }
        kick()
    }

    func kick() {
        Task { await run() }
    }

    /// Settings changed (key saved, AI toggled): forget failures and try again now.
    func settingsChanged() {
        failures = 0
        backoffUntil = nil
        failedCategoryKeys.removeAll()
        attemptedSuggestions.removeAll()
        kick()
    }

    private func networkCameBack() {
        guard backoffUntil != nil else { return }
        backoffUntil = nil
        kick()
    }

    func requestSummary(_ spec: SummarySpec) {
        guard AISettings.isActive, wantedSummaries[spec.key] != spec else { return }
        wantedSummaries[spec.key] = spec
        kick()
    }

    // MARK: - Run loop

    private func run() async {
        if isRunning {
            runAgain = true
            return
        }
        isRunning = true
        repeat {
            runAgain = false
            await runOnce()
        } while runAgain
        isRunning = false
    }

    private func runOnce() async {
        // Local work, always (works offline and without a key).
        store.applyCachedCategories()
        store.refreshLocalStopSuggestions()

        guard AISettings.isActive else {
            status = .off
            return
        }
        if let backoffUntil, backoffUntil > Date() {
            status = .waiting(until: backoffUntil, reason: status.waitingReason ?? "Will retry soon")
            scheduleRetry(at: backoffUntil)
            return
        }

        let service = LLMServices.current()
        status = .working
        do {
            try await processInterpretations(service)
            try await processCategories(service)
            try await processStopSuggestions(service)
            try await processSummaries(service)
            failures = 0
            backoffUntil = nil
            lastSuccess = Date()
            status = .idle
        } catch let error as LLMServiceError where error.isRetryable {
            backOff(error)
        } catch let error as LLMServiceError {
            // Invalid key etc.: stop until settings change.
            status = .needsAttention(error.userMessage)
        } catch {
            backOff(.network(String(describing: error)))
        }
    }

    private func backOff(_ error: LLMServiceError) {
        failures += 1
        var delay = min(3600, 30 * pow(2, Double(failures - 1)))
        if case .rateLimited(let retryAfter?) = error {
            delay = max(delay, retryAfter)
        }
        let until = Date().addingTimeInterval(delay)
        backoffUntil = until
        status = .waiting(until: until, reason: error.userMessage)
        scheduleRetry(at: until)
    }

    private func scheduleRetry(at date: Date) {
        retryTask?.cancel()
        retryTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(max(1, date.timeIntervalSinceNow)))
            guard !Task.isCancelled else { return }
            self?.kick()
        }
    }

    /// Errors that are about one item (not connectivity or the key) shouldn't block the whole queue.
    private func isItemError(_ error: Error) -> Bool {
        guard let error = error as? LLMServiceError else { return false }
        return !error.isRetryable && error != .invalidAPIKey && error != .notConfigured
    }

    // MARK: - Jobs

    private func processInterpretations(_ service: any LLMService) async throws {
        for recordID in store.pendingInterpretationIDs() {
            guard let prepared = store.interpretationRequest(for: recordID) else { continue }
            let (request, refs) = prepared
            do {
                let result = try await service.interpret(request)
                if store.applyInterpretation(result, recordID: recordID, refs: refs) {
                    await store.refreshSurfaces()
                }
            } catch let error where isItemError(error) {
                store.markInterpretationFailed(recordID: recordID)
            }
        }
    }

    private func processCategories(_ service: any LLMService) async throws {
        let missing = store.applyCachedCategories().filter { !failedCategoryKeys.contains($0.key) }
        guard !missing.isEmpty else { return }
        let items = missing.sorted { $0.key < $1.key }
        for start in stride(from: 0, to: items.count, by: 25) {
            let batch = Array(items[start..<min(start + 25, items.count)])
            let request = CategorizationRequest(activities: batch.map(\.value), existingCategories: store.knownCategories())
            do {
                let result = try await service.categorize(request)
                store.saveCategoryAssignments(result)
                for (key, _) in batch where result[key] == nil {
                    failedCategoryKeys.insert(key)
                }
            } catch let error where isItemError(error) {
                batch.forEach { failedCategoryKeys.insert($0.key) }
            }
        }
    }

    private func processStopSuggestions(_ service: any LLMService) async throws {
        for entryID in store.entriesWantingAISuggestion() where !attemptedSuggestions.contains(entryID) {
            guard let request = store.stopSuggestionRequest(for: entryID) else { continue }
            do {
                attemptedSuggestions.insert(entryID)
                if let suggestion = try await service.suggestStop(request) {
                    store.saveAISuggestion(suggestion, for: entryID)
                }
            } catch let error where isItemError(error) {
                continue
            } catch {
                attemptedSuggestions.remove(entryID)
                throw error
            }
        }
    }

    private func processSummaries(_ service: any LLMService) async throws {
        for spec in wantedSummaries.values.sorted(by: { $0.key < $1.key }) {
            let entries = store.summaryEntries(in: spec.interval, finishedOnly: true)
            let fingerprint = SummaryCalculator.fingerprint(entries, in: spec.interval)
            let totals = SummaryCalculator.categoryTotals(entries, in: spec.interval, now: spec.interval.end)
            guard !totals.isEmpty, store.summaryCache(key: spec.key)?.fingerprint != fingerprint else {
                wantedSummaries[spec.key] = nil
                continue
            }
            let request = SummaryRequest(
                period: spec.period,
                periodLabel: spec.label,
                totals: totals,
                topActivities: SummaryCalculator.activityTotals(entries, in: spec.interval, now: spec.interval.end)
            )
            do {
                let note = try await service.summarize(request)
                store.saveSummary(key: spec.key, fingerprint: fingerprint, note: note)
                wantedSummaries[spec.key] = nil
            } catch let error where isItemError(error) {
                wantedSummaries[spec.key] = nil
            }
        }
    }
}

extension AIWorker.Status {
    var waitingReason: String? {
        if case .waiting(_, let reason) = self { return reason }
        return nil
    }

    var description: String {
        switch self {
        case .off: "Off"
        case .idle: "Up to date"
        case .working: "Working\u{2026}"
        case .waiting(let until, let reason): "\(reason) Next try \(until.formatted(date: .omitted, time: .shortened))."
        case .needsAttention(let message): message
        }
    }
}
