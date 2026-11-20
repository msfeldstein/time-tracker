import Foundation

public struct SummaryEntry: Sendable, Equatable {
    public let name: String
    public let category: String?
    public let startedAt: Date
    public let endedAt: Date?

    public init(name: String, category: String?, startedAt: Date, endedAt: Date?) {
        self.name = name
        self.category = category
        self.startedAt = startedAt
        self.endedAt = endedAt
    }
}

public struct CategoryTotal: Sendable, Equatable, Identifiable {
    public let category: String
    public let seconds: TimeInterval
    public var id: String { category }
    public var minutes: Int { Int((seconds / 60).rounded()) }

    public init(category: String, seconds: TimeInterval) {
        self.category = category
        self.seconds = seconds
    }
}

public struct ActivityTotal: Sendable, Equatable {
    public let name: String
    public let category: String
    public let seconds: TimeInterval
    public let sessions: Int
    public var minutes: Int { Int((seconds / 60).rounded()) }

    public init(name: String, category: String, seconds: TimeInterval, sessions: Int) {
        self.name = name
        self.category = category
        self.seconds = seconds
        self.sessions = sessions
    }
}

/// Time per category for a day or week. Entries are clipped to the interval; running ones count up to `now`.
public enum SummaryCalculator {
    public static func categoryTotals(_ entries: [SummaryEntry], in interval: DateInterval, now: Date) -> [CategoryTotal] {
        var totals: [String: TimeInterval] = [:]
        for entry in entries {
            let seconds = clippedSeconds(entry, in: interval, now: now)
            guard seconds > 0 else { continue }
            totals[entry.category ?? CategoryDefaults.uncategorized, default: 0] += seconds
        }
        return totals
            .map { CategoryTotal(category: $0.key, seconds: $0.value) }
            .sorted { $0.seconds != $1.seconds ? $0.seconds > $1.seconds : $0.category < $1.category }
    }

    public static func activityTotals(_ entries: [SummaryEntry], in interval: DateInterval, now: Date, limit: Int = 8) -> [ActivityTotal] {
        var grouped: [String: (name: String, category: String, seconds: TimeInterval, sessions: Int)] = [:]
        for entry in entries {
            let seconds = clippedSeconds(entry, in: interval, now: now)
            guard seconds > 0 else { continue }
            let key = CategoryKey.normalize(entry.name)
            var current = grouped[key] ?? (entry.name, entry.category ?? CategoryDefaults.uncategorized, 0, 0)
            current.seconds += seconds
            current.sessions += 1
            grouped[key] = current
        }
        return grouped.values
            .map { ActivityTotal(name: $0.name, category: $0.category, seconds: $0.seconds, sessions: $0.sessions) }
            .sorted { $0.seconds != $1.seconds ? $0.seconds > $1.seconds : $0.name < $1.name }
            .prefix(limit)
            .map { $0 }
    }

    public static func clippedSeconds(_ entry: SummaryEntry, in interval: DateInterval, now: Date) -> TimeInterval {
        let end = min(entry.endedAt ?? now, interval.end)
        let start = max(entry.startedAt, interval.start)
        return max(0, end.timeIntervalSince(start))
    }

    /// Identifies the data a summary note was written from. Only finished activities count and minutes
    /// are rounded to 5, so a running timer doesn't invalidate the cached note every second.
    public static func fingerprint(_ entries: [SummaryEntry], in interval: DateInterval) -> String {
        let finished = entries.filter { $0.endedAt != nil }
        let totals = categoryTotals(finished, in: interval, now: interval.end)
        let activities = activityTotals(finished, in: interval, now: interval.end, limit: 50)
        let categoryPart = totals.map { "\($0.category)=\(Int(($0.seconds / 300).rounded()))" }
        let activityPart = activities.map { "\(CategoryKey.normalize($0.name))=\(Int(($0.seconds / 300).rounded()))x\($0.sessions)" }
        return (categoryPart + ["|"] + activityPart).joined(separator: ";")
    }

    /// Plain summary used offline or without AI.
    public static func localNote(totals: [CategoryTotal], period: SummaryPeriod) -> String {
        let total = totals.reduce(0) { $0 + $1.seconds }
        let when = period == .day ? "today" : "this week"
        guard total >= 60 else {
            return period == .day ? "Nothing tracked yet today." : "Nothing tracked yet this week."
        }
        let sorted = totals.filter { $0.category != CategoryDefaults.uncategorized }
        var note = "You tracked \(DurationFormatting.spoken(total)) \(when)"
        if let top = sorted.first {
            note += ", mostly \(top.category.lowercased()) (\(DurationFormatting.short(top.seconds)))"
        }
        return note + "."
    }
}
