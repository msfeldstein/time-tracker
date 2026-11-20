import Foundation
import SwiftData

enum EntryKind: String, Codable, Sendable {
    case activity
    case note
}

enum EntrySource: String, Codable, Sendable {
    case voice
    case siri
    case widget
    case liveActivity
    case manual
}

/// One timed activity ("Dishes", 9:05–9:32) or one free-text note.
@Model
final class TimeEntry {
    var id: UUID = UUID()
    var kindRaw: String = EntryKind.activity.rawValue
    var name: String = ""
    var startedAt: Date = Date()
    /// `nil` while the activity is running. Notes have `endedAt == startedAt`.
    var endedAt: Date?
    /// The exact words that created this entry.
    var rawTranscript: String = ""
    var sourceRaw: String = EntrySource.voice.rawValue
    var createdAt: Date = Date()
    /// Life category ("Chores", "Kids"...), set from the category cache, the LLM, or by hand.
    var category: String?
    var categorySourceRaw: String?

    /// The capture whose words created this entry.
    var captureID: UUID?
    /// The capture whose words stopped this entry.
    var stoppedByCaptureID: UUID?
    /// Set when an AI interpretation created, stopped or reopened this entry (undoable).
    var interpretationID: UUID?
    /// Notes hidden because an AI interpretation replaced them (restored on undo).
    var supersededByInterpretationID: UUID?

    /// "Forgot to stop?" suggestion. Never applied automatically.
    var suggestedEndAt: Date?
    var suggestionReason: String?
    var suggestionSourceRaw: String?
    /// The start time the suggestion was computed for; a stale suggestion is recomputed.
    var suggestionForStartedAt: Date?

    init(
        kind: EntryKind,
        name: String,
        startedAt: Date,
        endedAt: Date? = nil,
        rawTranscript: String,
        source: EntrySource
    ) {
        self.id = UUID()
        self.kindRaw = kind.rawValue
        self.name = name
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.rawTranscript = rawTranscript
        self.sourceRaw = source.rawValue
        self.createdAt = Date()
    }

    var kind: EntryKind { EntryKind(rawValue: kindRaw) ?? .activity }
    var source: EntrySource { EntrySource(rawValue: sourceRaw) ?? .manual }
    var isRunning: Bool { kind == .activity && endedAt == nil }
    var categorySource: CategorySource? { categorySourceRaw.flatMap(CategorySource.init(rawValue:)) }
    var suggestionSource: SuggestionSource? { suggestionSourceRaw.flatMap(SuggestionSource.init(rawValue:)) }

    /// A stop suggestion that still matches this running entry.
    var activeSuggestion: Date? {
        guard isRunning, let suggestedEndAt, suggestionForStartedAt == startedAt else { return nil }
        return suggestedEndAt
    }

    func duration(now: Date = Date()) -> TimeInterval {
        (endedAt ?? now).timeIntervalSince(startedAt)
    }
}

/// Every transcript is written here first, before it is interpreted, so nothing she says is lost
/// even if parsing or the app crashes. `interpretedAt == nil` means it still needs processing.
@Model
final class CaptureRecord {
    var id: UUID = UUID()
    var text: String = ""
    var capturedAt: Date = Date()
    var sourceRaw: String = EntrySource.voice.rawValue
    var interpretedAt: Date?
    var outcome: String?

    /// LLM fallback state for transcripts the local parser couldn't handle confidently.
    var aiStatusRaw: String = AIStatus.none.rawValue
    var aiAttempts: Int = 0
    var aiSummary: String?
    /// Entries this capture stopped through a weak or ambiguous match.
    var lowConfidenceStopIDs: [UUID] = []

    init(text: String, capturedAt: Date, source: EntrySource) {
        self.id = UUID()
        self.text = text
        self.capturedAt = capturedAt
        self.sourceRaw = source.rawValue
    }

    var source: EntrySource { EntrySource(rawValue: sourceRaw) ?? .voice }
    var aiStatus: AIStatus {
        get { AIStatus(rawValue: aiStatusRaw) ?? .none }
        set { aiStatusRaw = newValue.rawValue }
    }
}

enum AIStatus: String, Codable, Sendable {
    /// The local parser was confident; no LLM needed.
    case none
    /// Waiting for the LLM (queued; retried when online).
    case pending
    /// The LLM's interpretation was applied (see `AIInterpretation`).
    case applied
    /// The LLM agreed with the local result, or wasn't confident.
    case unchanged
    case reverted
    case failed
    /// Too old by the time the LLM was available.
    case skipped
}

enum CategorySource: String, Codable, Sendable {
    case cache
    case ai
    case user
}

enum SuggestionSource: String, Codable, Sendable {
    /// Local heuristic: start + usual length.
    case usual
    case ai
}

/// Cache from a normalized activity name ("dish") to its category, so repeat activities never need a call.
@Model
final class CategoryAssignment {
    var key: String = ""
    var category: String = ""
    var sourceRaw: String = CategorySource.ai.rawValue
    var updatedAt: Date = Date()

    init(key: String, category: String, source: CategorySource) {
        self.key = key
        self.category = category
        self.sourceRaw = source.rawValue
        self.updatedAt = Date()
    }
}

/// A reversible record of what an LLM interpretation changed, so "Undo" restores the local result exactly.
@Model
final class AIInterpretation {
    var id: UUID = UUID()
    var captureID: UUID = UUID()
    var createdAt: Date = Date()
    var summary: String = ""
    var createdEntryIDs: [UUID] = []
    var stoppedEntryIDs: [UUID] = []
    var reopenedEntryIDs: [UUID] = []
    var reopenedPreviousEnds: [Date] = []
    var supersededNoteIDs: [UUID] = []
    var revertedAt: Date?

    init(captureID: UUID) {
        self.id = UUID()
        self.captureID = captureID
        self.createdAt = Date()
    }
}

/// Last LLM-written summary note per period, regenerated only when the underlying data changes.
@Model
final class SummaryCache {
    var key: String = ""
    var fingerprint: String = ""
    var note: String = ""
    var generatedAt: Date = Date()

    init(key: String, fingerprint: String, note: String) {
        self.key = key
        self.fingerprint = fingerprint
        self.note = note
        self.generatedAt = Date()
    }
}

/// A Sendable copy of a running entry, for widgets, Live Activities and intents.
struct RunningSnapshot: Sendable, Hashable, Codable {
    let id: UUID
    let name: String
    let startedAt: Date

    init(id: UUID, name: String, startedAt: Date) {
        self.id = id
        self.name = name
        self.startedAt = startedAt
    }

    init(_ entry: TimeEntry) {
        self.init(id: entry.id, name: entry.name, startedAt: entry.startedAt)
    }
}
