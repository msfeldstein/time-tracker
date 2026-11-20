import Foundation

/// Cleans the optional build-time key that arrives through Info.plist from `ANTHROPIC_API_KEY`
/// in the git-ignored Config/Local.xcconfig.
public enum BundledAPIKey {
    /// Returns the usable key, or nil when the setting is empty, unexpanded, or obviously mangled.
    public static func sanitize(_ raw: String?) -> String? {
        guard var value = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else { return nil }
        // xcconfig keeps quotes literally; accept a quoted value anyway.
        if value.count >= 2, let first = value.first, first == value.last, first == "\"" || first == "'" {
            value = String(value.dropFirst().dropLast()).trimmingCharacters(in: .whitespaces)
        }
        // "$(ANTHROPIC_API_KEY)" left unexpanded means the setting doesn't exist for this target.
        guard !value.isEmpty, !value.contains("$("), !value.contains(where: \.isWhitespace) else { return nil }
        return value
    }
}
