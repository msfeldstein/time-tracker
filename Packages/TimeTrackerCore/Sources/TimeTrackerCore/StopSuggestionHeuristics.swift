import Foundation

/// Decides when a running activity has gone on "far longer than typical", and makes a local
/// best guess at its real end time. Works offline; the LLM can refine the guess.
public enum StopSuggestionHeuristics {
    /// With no history, anything over this is considered forgotten.
    public static let defaultThreshold: TimeInterval = DurationFormatting.forgotToStopThreshold

    /// Median of past durations, if there are at least two.
    public static func typicalDuration(_ history: [TimeInterval]) -> TimeInterval? {
        let sorted = history.filter { $0 > 0 }.sorted()
        guard sorted.count >= 2 else { return nil }
        let middle = sorted.count / 2
        return sorted.count.isMultiple(of: 2) ? (sorted[middle - 1] + sorted[middle]) / 2 : sorted[middle]
    }

    /// How long a run can last before it looks forgotten.
    public static func threshold(typical: TimeInterval?) -> TimeInterval {
        guard let typical else { return defaultThreshold }
        return min(defaultThreshold * 2, max(typical * 3, typical + 45 * 60, 60 * 60))
    }

    public static func looksForgotten(elapsed: TimeInterval, typical: TimeInterval?) -> Bool {
        elapsed > threshold(typical: typical)
    }

    /// Local guess: start + typical length (or 1 hour), never later than now.
    public static func localSuggestion(startedAt: Date, typical: TimeInterval?, now: Date) -> Date {
        min(now, startedAt.addingTimeInterval(typical ?? 60 * 60))
    }

    /// Keeps a suggested end inside (start + 1 minute) ... now.
    public static func clamp(_ end: Date, startedAt: Date, now: Date) -> Date {
        min(max(end, startedAt.addingTimeInterval(60)), now)
    }
}
