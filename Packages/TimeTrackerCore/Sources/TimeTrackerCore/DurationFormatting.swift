import Foundation

public enum DurationFormatting {
    /// Entries running longer than this are flagged "forgot to stop?".
    public static let forgotToStopThreshold: TimeInterval = 3 * 60 * 60

    /// "45s", "12m", "1h 05m".
    public static func short(_ interval: TimeInterval) -> String {
        let total = max(0, Int(interval.rounded(.down)))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let seconds = total % 60
        if hours > 0 {
            return "\(hours)h " + (minutes < 10 ? "0\(minutes)m" : "\(minutes)m")
        }
        if minutes > 0 {
            return "\(minutes)m"
        }
        return "\(seconds)s"
    }

    /// "1 hour 5 minutes", for VoiceOver and Siri dialogs.
    public static func spoken(_ interval: TimeInterval) -> String {
        let total = max(0, Int(interval.rounded(.down)))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        var parts: [String] = []
        if hours > 0 { parts.append(hours == 1 ? "1 hour" : "\(hours) hours") }
        if minutes > 0 { parts.append(minutes == 1 ? "1 minute" : "\(minutes) minutes") }
        if parts.isEmpty { return total == 1 ? "1 second" : "\(total) seconds" }
        return parts.joined(separator: " ")
    }

    public static func isProbablyForgotten(startedAt: Date, endedAt: Date?, now: Date = Date()) -> Bool {
        (endedAt ?? now).timeIntervalSince(startedAt) > forgotToStopThreshold
    }
}
