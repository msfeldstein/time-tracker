import Foundation
import SwiftData
import TimeTrackerCore
import WidgetKit
import os

struct CaptureOutcome: Sendable {
    let message: String
}

/// All writes go through here so the widget and Live Activity are refreshed after every change.
@MainActor
final class EntryService {
    static let shared = EntryService()

    let context: ModelContext
    private let logger = Logger(subsystem: "TimeTracker", category: "EntryService")

    private init() {
        context = SharedStore.container.mainContext
    }

    // MARK: - Reading

    func runningEntries() -> [TimeEntry] {
        let activity = EntryKind.activity.rawValue
        let descriptor = FetchDescriptor<TimeEntry>(
            predicate: #Predicate<TimeEntry> { $0.endedAt == nil && $0.kindRaw == activity },
            sortBy: [SortDescriptor(\.startedAt, order: .reverse)]
        )
        return (try? context.fetch(descriptor)) ?? []
    }

    func findEntry(id: UUID) -> TimeEntry? {
        var descriptor = FetchDescriptor<TimeEntry>(predicate: #Predicate<TimeEntry> { $0.id == id })
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }

    // MARK: - Voice capture

    /// Saves the raw transcript first, then interprets it. Unparseable text becomes a note.
    @discardableResult
    func capture(text: String, source: EntrySource, at date: Date = Date()) async -> CaptureOutcome {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return CaptureOutcome(message: "I didn't catch anything.")
        }
        let record = CaptureRecord(text: trimmed, capturedAt: date, source: source)
        context.insert(record)
        save()

        let message = interpret(record, commands: CommandParser.parse(trimmed))
        save()
        await refreshSurfaces()
        return CaptureOutcome(message: message)
    }

    /// Siri "Start activity": the spoken parameter is the activity name, but tolerate "starting dishes".
    func startFromIntent(_ spoken: String, source: EntrySource) async -> CaptureOutcome {
        let trimmed = spoken.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return CaptureOutcome(message: "What are you starting?") }
        var commands = CommandParser.parse(trimmed).filter { if case .start = $0 { true } else { false } }
        if commands.isEmpty {
            let cleaned = CommandParser.cleanActivity(TextNormalizer.words(TextNormalizer.normalize(trimmed)))
            commands = [.start(activity: cleaned.isEmpty ? trimmed : cleaned)]
        }
        return await record(text: trimmed, commands: commands, source: source)
    }

    /// Siri "Stop activity": with no name, stops the most recent one.
    func stopFromIntent(_ spoken: String?, source: EntrySource) async -> CaptureOutcome {
        let trimmed = spoken?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if trimmed.isEmpty {
            return await record(text: "stop", commands: [.stop(activity: nil)], source: source)
        }
        var commands = CommandParser.parse("stop \(trimmed)").filter {
            switch $0 {
            case .stop, .stopAll: true
            default: false
            }
        }
        if commands.isEmpty { commands = [.stop(activity: trimmed)] }
        return await record(text: "stop \(trimmed)", commands: commands, source: source)
    }

    private func record(text: String, commands: [ParsedCommand], source: EntrySource) async -> CaptureOutcome {
        let record = CaptureRecord(text: text, capturedAt: Date(), source: source)
        context.insert(record)
        save()
        let message = interpret(record, commands: commands)
        save()
        await refreshSurfaces()
        return CaptureOutcome(message: message)
    }

    /// Finishes interpreting transcripts that were saved but not processed (e.g. the app was killed mid-way).
    func reprocessPendingCaptures() async {
        let descriptor = FetchDescriptor<CaptureRecord>(
            predicate: #Predicate<CaptureRecord> { $0.interpretedAt == nil },
            sortBy: [SortDescriptor(\.capturedAt)]
        )
        guard let pending = try? context.fetch(descriptor), !pending.isEmpty else { return }
        for record in pending {
            _ = interpret(record, commands: CommandParser.parse(record.text))
        }
        save()
        await refreshSurfaces()
    }

    private func interpret(_ record: CaptureRecord, commands: [ParsedCommand]) -> String {
        let running = runningEntries()
        let plan = CommandResolver.resolve(
            commands,
            running: running.map { RunningActivity(id: $0.id, name: $0.name, startedAt: $0.startedAt) },
            rawText: record.text
        )

        var messages: [String] = []
        for action in plan {
            switch action {
            case .start(let name):
                context.insert(TimeEntry(
                    kind: .activity, name: name, startedAt: record.capturedAt,
                    rawTranscript: record.text, source: record.source
                ))
                messages.append("Started \(name)")

            case .stop(let id):
                guard let entry = running.first(where: { $0.id == id }) else { continue }
                entry.endedAt = max(record.capturedAt, entry.startedAt)
                messages.append("Stopped \(entry.name) · \(DurationFormatting.short(entry.duration()))")

            case .alreadyRunning(let id):
                let name = running.first(where: { $0.id == id })?.name ?? "That"
                messages.append("\(name) is already running")

            case .note(let text):
                insertNote(text: text, record: record)
                messages.append("Saved as a note")

            case .noMatch(let query, let text):
                insertNote(text: text, record: record)
                messages.append("Nothing called \u{201C}\(query)\u{201D} is running, so I saved it as a note")

            case .nothingRunning:
                messages.append("Nothing is running right now")
            }
        }

        let outcome = messages.isEmpty ? "Saved" : messages.joined(separator: "\n")
        record.interpretedAt = Date()
        record.outcome = outcome
        return outcome
    }

    private func insertNote(text: String, record: CaptureRecord) {
        context.insert(TimeEntry(
            kind: .note, name: text, startedAt: record.capturedAt, endedAt: record.capturedAt,
            rawTranscript: record.text, source: record.source
        ))
    }

    // MARK: - Direct edits (taps, Live Activity button, Today view)

    func stop(entryID: UUID, at date: Date = Date()) async {
        guard let entry = findEntry(id: entryID), entry.isRunning else { return }
        entry.endedAt = max(date, entry.startedAt)
        save()
        await refreshSurfaces()
    }

    func addManualEntry(name: String, startedAt: Date, endedAt: Date?) async {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        context.insert(TimeEntry(
            kind: .activity, name: TextNormalizer.displayName(trimmed), startedAt: startedAt,
            endedAt: endedAt, rawTranscript: "", source: .manual
        ))
        save()
        await refreshSurfaces()
    }

    func delete(_ entry: TimeEntry) async {
        context.delete(entry)
        save()
        await refreshSurfaces()
    }

    /// Call after editing a `TimeEntry`'s properties directly.
    func commitEdits() async {
        save()
        await refreshSurfaces()
    }

    // MARK: - Side effects

    func refreshSurfaces() async {
        WidgetCenter.shared.reloadAllTimelines()
        await LiveActivityManager.sync(running: runningEntries().map(RunningSnapshot.init))
    }

    private func save() {
        guard context.hasChanges else { return }
        do {
            try context.save()
        } catch {
            // Changes stay in the context and autosave retries; log so it shows in Console.
            logger.fault("Save failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}
