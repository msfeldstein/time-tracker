import Foundation
import SwiftData
import TimeTrackerCore

/// SwiftData side of the AI features. Network calls live in `AIWorker`; everything here is local,
/// so cached categories, "usual length" stop suggestions and summaries work offline.
extension EntryService {
    private var activityKind: String { EntryKind.activity.rawValue }

    // MARK: - Categories

    func categoryCache() -> [String: CategoryAssignment] {
        let all = (try? context.fetch(FetchDescriptor<CategoryAssignment>())) ?? []
        return Dictionary(all.map { ($0.key, $0) }, uniquingKeysWith: { first, _ in first })
    }

    /// The defaults plus any categories that have been used, so the LLM keeps names stable across days.
    func knownCategories() -> [String] {
        var names = CategoryDefaults.names
        let used = Set(categoryCache().values.map(\.category))
        for name in used.sorted() where !names.contains(name) {
            names.append(name)
        }
        return names
    }

    /// Fills in categories for finished activities from the cache. Returns `[key: display name]`
    /// for activities the cache doesn't know yet (those need one batched LLM call).
    @discardableResult
    func applyCachedCategories() -> [String: String] {
        let kind = activityKind
        let descriptor = FetchDescriptor<TimeEntry>(
            predicate: #Predicate<TimeEntry> { $0.kindRaw == kind && $0.category == nil && $0.endedAt != nil }
        )
        let uncategorized = (try? context.fetch(descriptor)) ?? []
        guard !uncategorized.isEmpty else { return [:] }
        let cache = categoryCache()
        var missing: [String: String] = [:]
        var changed = false
        for entry in uncategorized {
            let key = CategoryKey.normalize(entry.name)
            guard !key.isEmpty else { continue }
            if let cached = cache[key] {
                entry.category = cached.category
                entry.categorySourceRaw = CategorySource.cache.rawValue
                changed = true
            } else if missing[key] == nil {
                missing[key] = entry.name
            }
        }
        if changed { save() }
        return missing
    }

    func saveCategoryAssignments(_ assignments: [String: String]) {
        guard !assignments.isEmpty else { return }
        let cache = categoryCache()
        for (key, category) in assignments {
            if let existing = cache[key] {
                guard existing.sourceRaw != CategorySource.user.rawValue else { continue }
                existing.category = category
                existing.updatedAt = Date()
            } else {
                context.insert(CategoryAssignment(key: key, category: category, source: .ai))
            }
        }
        save()
        applyCachedCategories()
    }

    /// A category chosen by hand. It also becomes the cached category for this activity from now on.
    func setCategory(_ category: String, for entry: TimeEntry) async {
        let key = CategoryKey.normalize(entry.name)
        entry.category = category
        entry.categorySourceRaw = CategorySource.user.rawValue
        if let existing = categoryCache()[key] {
            existing.category = category
            existing.sourceRaw = CategorySource.user.rawValue
            existing.updatedAt = Date()
        } else if !key.isEmpty {
            context.insert(CategoryAssignment(key: key, category: category, source: .user))
        }
        save()
        await refreshSurfaces()
    }

    // MARK: - Interpretation fallback

    func captureRecord(id: UUID) -> CaptureRecord? {
        var descriptor = FetchDescriptor<CaptureRecord>(predicate: #Predicate<CaptureRecord> { $0.id == id })
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }

    /// Captures waiting for the LLM, oldest first. Ones older than 3 days are skipped: by then
    /// she has likely fixed things by hand.
    func pendingInterpretationIDs(limit: Int = 5) -> [UUID] {
        let pending = AIStatus.pending.rawValue
        let descriptor = FetchDescriptor<CaptureRecord>(
            predicate: #Predicate<CaptureRecord> { $0.aiStatusRaw == pending },
            sortBy: [SortDescriptor(\.capturedAt)]
        )
        let records = (try? context.fetch(descriptor)) ?? []
        let cutoff = Date().addingTimeInterval(-3 * 86400)
        var ids: [UUID] = []
        var changed = false
        for record in records {
            if record.capturedAt < cutoff {
                record.aiStatus = .skipped
                changed = true
            } else if ids.count < limit {
                ids.append(record.id)
            }
        }
        if changed { save() }
        return ids
    }

    /// What was running when she spoke, with short refs instead of database ids.
    func interpretationRequest(for recordID: UUID) -> (InterpretationRequest, [String: UUID])? {
        guard let record = captureRecord(id: recordID) else { return nil }
        let spokenAt = record.capturedAt
        let earliest = spokenAt.addingTimeInterval(-2 * 86400)
        let kind = activityKind
        let descriptor = FetchDescriptor<TimeEntry>(
            predicate: #Predicate<TimeEntry> { $0.kindRaw == kind && $0.startedAt <= spokenAt && $0.startedAt >= earliest },
            sortBy: [SortDescriptor(\.startedAt, order: .reverse)]
        )
        let candidates = ((try? context.fetch(descriptor)) ?? []).filter { entry in
            entry.captureID != recordID && entry.supersededByInterpretationID == nil
                && (entry.endedAt == nil || entry.endedAt! >= spokenAt)
        }
        var refs: [String: UUID] = [:]
        var running: [LLMRunningActivity] = []
        for (index, entry) in candidates.prefix(12).enumerated() {
            let ref = "r\(index + 1)"
            refs[ref] = entry.id
            running.append(LLMRunningActivity(ref: ref, name: entry.name, startedAt: entry.startedAt))
        }
        return (InterpretationRequest(transcript: record.text, running: running, spokenAt: spokenAt), refs)
    }

    /// Applies the LLM's reading on top of the local one, recording every change so it can be undone.
    /// Returns true if anything changed.
    @discardableResult
    func applyInterpretation(_ result: InterpretationResult, recordID: UUID, refs: [String: UUID]) -> Bool {
        guard let record = captureRecord(id: recordID), record.aiStatus == .pending else { return false }
        guard result.confidence >= InterpretationResult.minimumConfidence, !result.events.isEmpty else {
            record.aiStatus = .unchanged
            save()
            return false
        }

        let interpretation = AIInterpretation(captureID: record.id)
        let fromThisCapture = entries(createdBy: record.id)
        var changes: [String] = []
        var stoppedByAI = Set<UUID>()
        var aiHasStops = false
        var aiHasNotes = false

        for event in result.events {
            switch event {
            case .start(let activity, let minutesAgo):
                let name = TextNormalizer.displayName(activity)
                let duplicate = (runningEntries() + fromThisCapture.filter { $0.kind == .activity })
                    .contains { ActivityMatcher.score($0.name, name) >= 0.99 }
                guard !duplicate else { continue }
                let entry = TimeEntry(
                    kind: .activity, name: name,
                    startedAt: record.capturedAt.addingTimeInterval(-TimeInterval(minutesAgo) * 60),
                    rawTranscript: record.text, source: record.source
                )
                entry.captureID = record.id
                entry.interpretationID = interpretation.id
                context.insert(entry)
                interpretation.createdEntryIDs.append(entry.id)
                changes.append("Started \(name)")

            case .stop(let ref):
                aiHasStops = true
                guard let id = refs[ref], let entry = findEntry(id: id) else { continue }
                stoppedByAI.insert(id)
                if entry.endedAt == nil {
                    entry.endedAt = max(record.capturedAt, entry.startedAt)
                    entry.stoppedByCaptureID = record.id
                    entry.interpretationID = interpretation.id
                    interpretation.stoppedEntryIDs.append(id)
                    changes.append("Stopped \(entry.name)")
                }

            case .note:
                aiHasNotes = true
            }
        }

        // A weak local match the LLM didn't agree with (it chose a different activity) is reopened.
        if aiHasStops {
            for id in record.lowConfidenceStopIDs where !stoppedByAI.contains(id) {
                guard let entry = findEntry(id: id), entry.stoppedByCaptureID == record.id, let previous = entry.endedAt else { continue }
                entry.endedAt = nil
                entry.stoppedByCaptureID = nil
                entry.interpretationID = interpretation.id
                interpretation.reopenedEntryIDs.append(id)
                interpretation.reopenedPreviousEnds.append(previous)
                changes.append("Kept \(entry.name) running")
            }
        }

        guard !changes.isEmpty else {
            record.aiStatus = .unchanged
            save()
            return false
        }

        // The raw note stays in the store, just hidden while the interpretation stands.
        if !aiHasNotes {
            for note in fromThisCapture where note.kind == .note && note.supersededByInterpretationID == nil {
                note.supersededByInterpretationID = interpretation.id
                interpretation.supersededNoteIDs.append(note.id)
            }
        }

        interpretation.summary = changes.joined(separator: ", ")
        context.insert(interpretation)
        record.aiStatus = .applied
        record.aiSummary = interpretation.summary
        save()
        return true
    }

    func markInterpretationFailed(recordID: UUID) {
        guard let record = captureRecord(id: recordID) else { return }
        record.aiAttempts += 1
        if record.aiAttempts >= 3 {
            record.aiStatus = .failed
        }
        save()
    }

    func interpretation(id: UUID) -> AIInterpretation? {
        var descriptor = FetchDescriptor<AIInterpretation>(predicate: #Predicate<AIInterpretation> { $0.id == id })
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }

    /// Restores exactly what the local parser produced before the LLM's interpretation.
    func revertInterpretation(id: UUID) async {
        guard let interpretation = interpretation(id: id), interpretation.revertedAt == nil else { return }
        for entryID in interpretation.createdEntryIDs {
            if let entry = findEntry(id: entryID) { context.delete(entry) }
        }
        for entryID in interpretation.stoppedEntryIDs {
            guard let entry = findEntry(id: entryID) else { continue }
            entry.endedAt = nil
            entry.stoppedByCaptureID = nil
            entry.interpretationID = nil
        }
        for (index, entryID) in interpretation.reopenedEntryIDs.enumerated() {
            guard let entry = findEntry(id: entryID), index < interpretation.reopenedPreviousEnds.count else { continue }
            entry.endedAt = interpretation.reopenedPreviousEnds[index]
            entry.stoppedByCaptureID = interpretation.captureID
            entry.interpretationID = nil
        }
        for noteID in interpretation.supersededNoteIDs {
            findEntry(id: noteID)?.supersededByInterpretationID = nil
        }
        interpretation.revertedAt = Date()
        captureRecord(id: interpretation.captureID)?.aiStatus = .reverted
        save()
        await refreshSurfaces()
    }

    private func entries(createdBy captureID: UUID) -> [TimeEntry] {
        let target: UUID? = captureID
        let descriptor = FetchDescriptor<TimeEntry>(predicate: #Predicate<TimeEntry> { $0.captureID == target })
        return (try? context.fetch(descriptor)) ?? []
    }

    // MARK: - Forgotten stops

    /// Past finished sessions of the same activity (newest first) and their median length.
    func history(for entry: TimeEntry, limit: Int = 20) -> (typical: TimeInterval?, sessions: [PastSession]) {
        let key = CategoryKey.normalize(entry.name)
        let kind = activityKind
        let since = Date().addingTimeInterval(-120 * 86400)
        let entryID = entry.id
        let descriptor = FetchDescriptor<TimeEntry>(
            predicate: #Predicate<TimeEntry> { $0.kindRaw == kind && $0.endedAt != nil && $0.startedAt >= since && $0.id != entryID },
            sortBy: [SortDescriptor(\.startedAt, order: .reverse)]
        )
        let past = ((try? context.fetch(descriptor)) ?? [])
            .filter { CategoryKey.normalize($0.name) == key }
            .prefix(limit)
        let durations = past.map { $0.duration() }
        let sessions = past.map { PastSession(startedAt: $0.startedAt, minutes: Int(($0.duration() / 60).rounded())) }
        return (StopSuggestionHeuristics.typicalDuration(durations), sessions)
    }

    /// Adds a local "usual length" suggestion to running activities that look forgotten.
    /// Never stops anything; she taps "Use suggestion" to apply it.
    func refreshLocalStopSuggestions(now: Date = Date()) {
        var changed = false
        for entry in runningEntries() {
            let typical = history(for: entry).typical
            let forgotten = StopSuggestionHeuristics.looksForgotten(elapsed: now.timeIntervalSince(entry.startedAt), typical: typical)
            if forgotten {
                guard entry.activeSuggestion == nil else { continue }
                entry.suggestedEndAt = StopSuggestionHeuristics.localSuggestion(startedAt: entry.startedAt, typical: typical, now: now)
                entry.suggestionReason = typical.map { "About your usual \(DurationFormatting.short($0))" } ?? "About an hour after you started"
                entry.suggestionSourceRaw = SuggestionSource.usual.rawValue
                entry.suggestionForStartedAt = entry.startedAt
                changed = true
            } else if entry.suggestedEndAt != nil {
                entry.suggestedEndAt = nil
                entry.suggestionReason = nil
                entry.suggestionSourceRaw = nil
                entry.suggestionForStartedAt = nil
                changed = true
            }
        }
        if changed { save() }
    }

    func entriesWantingAISuggestion() -> [UUID] {
        runningEntries()
            .filter { $0.activeSuggestion != nil && $0.suggestionSource == .usual }
            .map(\.id)
    }

    func stopSuggestionRequest(for entryID: UUID, now: Date = Date()) -> StopSuggestionRequest? {
        guard let entry = findEntry(id: entryID), entry.isRunning else { return nil }
        let (typical, sessions) = history(for: entry, limit: 10)
        let start = entry.startedAt
        let kind = activityKind
        let descriptor = FetchDescriptor<TimeEntry>(
            predicate: #Predicate<TimeEntry> { $0.kindRaw == kind && $0.startedAt > start && $0.id != entryID },
            sortBy: [SortDescriptor(\.startedAt)]
        )
        let later = ((try? context.fetch(descriptor)) ?? []).prefix(8).map {
            PastSession(startedAt: $0.startedAt, minutes: $0.endedAt == nil ? 0 : Int(($0.duration(now: now) / 60).rounded()))
        }
        return StopSuggestionRequest(
            activity: entry.name, category: entry.category ?? categoryCache()[CategoryKey.normalize(entry.name)]?.category,
            startedAt: start, now: now, typicalMinutes: typical.map { Int(($0 / 60).rounded()) },
            history: sessions, laterActivities: later
        )
    }

    func saveAISuggestion(_ suggestion: StopSuggestion, for entryID: UUID) {
        guard let entry = findEntry(id: entryID), entry.isRunning else { return }
        entry.suggestedEndAt = suggestion.endedAt
        entry.suggestionReason = suggestion.reason
        entry.suggestionSourceRaw = SuggestionSource.ai.rawValue
        entry.suggestionForStartedAt = entry.startedAt
        save()
    }

    /// The one-tap "Use suggestion" fix.
    func useSuggestion(entryID: UUID) async {
        guard let entry = findEntry(id: entryID), let end = entry.activeSuggestion else { return }
        entry.endedAt = StopSuggestionHeuristics.clamp(end, startedAt: entry.startedAt, now: Date())
        entry.suggestedEndAt = nil
        entry.suggestionReason = nil
        entry.suggestionSourceRaw = nil
        entry.suggestionForStartedAt = nil
        save()
        await refreshSurfaces()
    }

    // MARK: - Summaries

    func summaryEntries(in interval: DateInterval, finishedOnly: Bool) -> [SummaryEntry] {
        let kind = activityKind
        let from = interval.start.addingTimeInterval(-86400)
        let to = interval.end
        let descriptor = FetchDescriptor<TimeEntry>(
            predicate: #Predicate<TimeEntry> { $0.kindRaw == kind && $0.startedAt >= from && $0.startedAt < to }
        )
        let cache = categoryCache()
        return ((try? context.fetch(descriptor)) ?? [])
            .filter { !finishedOnly || $0.endedAt != nil }
            .map { entry in
                SummaryEntry(
                    name: entry.name,
                    category: entry.category ?? cache[CategoryKey.normalize(entry.name)]?.category,
                    startedAt: entry.startedAt,
                    endedAt: entry.endedAt
                )
            }
    }

    func summaryCache(key: String) -> SummaryCache? {
        var descriptor = FetchDescriptor<SummaryCache>(predicate: #Predicate<SummaryCache> { $0.key == key })
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }

    func saveSummary(key: String, fingerprint: String, note: String) {
        if let existing = summaryCache(key: key) {
            existing.fingerprint = fingerprint
            existing.note = note
            existing.generatedAt = Date()
        } else {
            context.insert(SummaryCache(key: key, fingerprint: fingerprint, note: note))
        }
        save()
    }
}
