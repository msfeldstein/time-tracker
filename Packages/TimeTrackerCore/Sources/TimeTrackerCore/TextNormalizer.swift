import Foundation

/// Lower-cases speech transcripts and strips punctuation so the parser can work on plain words.
public enum TextNormalizer {
    public static func normalize(_ text: String) -> String {
        let unified = text
            .replacingOccurrences(of: "\u{2019}", with: "'")
            .replacingOccurrences(of: "\u{2018}", with: "'")
            .lowercased()

        var scalars = String.UnicodeScalarView()
        for scalar in unified.unicodeScalars {
            if CharacterSet.alphanumerics.contains(scalar) || scalar == "'" {
                scalars.append(scalar)
            } else if scalar == "&" {
                scalars.append(contentsOf: " and ".unicodeScalars)
            } else {
                scalars.append(" ")
            }
        }
        return words(String(scalars)).joined(separator: " ")
    }

    public static func words(_ text: String) -> [String] {
        text.split(whereSeparator: { $0 == " " || $0 == "\n" || $0 == "\t" })
            .map { $0.trimmingCharacters(in: CharacterSet(charactersIn: "'")) }
            .filter { !$0.isEmpty }
    }

    /// Display form of an activity name: "washing the car" -> "Washing the car".
    public static func displayName(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let first = trimmed.first else { return trimmed }
        return first.uppercased() + trimmed.dropFirst()
    }
}
