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
    /// Reserved for milestone 2 auto-categorization.
    var category: String?

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

    init(text: String, capturedAt: Date, source: EntrySource) {
        self.id = UUID()
        self.text = text
        self.capturedAt = capturedAt
        self.sourceRaw = source.rawValue
    }

    var source: EntrySource { EntrySource(rawValue: sourceRaw) ?? .voice }
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
