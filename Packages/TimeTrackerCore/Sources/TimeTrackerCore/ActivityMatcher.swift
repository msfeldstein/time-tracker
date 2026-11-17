import Foundation

/// Fuzzy-matches spoken stop phrases ("the dishes", "dish washing") to running activity names ("Dishes").
public enum ActivityMatcher {
    public static let defaultThreshold = 0.55

    /// Returns the index of the best candidate, or nil if nothing scores above `threshold`.
    /// Ties go to the earlier candidate, so pass candidates most-recent first.
    public static func bestMatch(for query: String, in candidates: [String], threshold: Double = defaultThreshold) -> Int? {
        var best: (index: Int, score: Double)?
        for (index, candidate) in candidates.enumerated() {
            let value = score(query, candidate)
            if value >= threshold, value > (best?.score ?? -1) {
                best = (index, value)
            }
        }
        return best?.index
    }

    /// Similarity in 0...1.
    public static func score(_ a: String, _ b: String) -> Double {
        let left = keyTokens(a)
        let right = keyTokens(b)
        guard !left.isEmpty, !right.isEmpty else { return 0 }
        if left == right { return 1 }

        var matched = 0
        var remaining = right
        for token in left {
            if let hit = remaining.firstIndex(where: { tokensMatch(token, $0) }) {
                matched += 1
                remaining.remove(at: hit)
            }
        }
        let overlap = Double(matched) / Double(min(left.count, right.count))
        let union = Double(left.count + right.count - matched)
        let jaccard = Double(matched) / union
        let tokenScore = overlap * 0.85 + jaccard * 0.15

        let joinedScore = similarity(left.joined(separator: " "), right.joined(separator: " "))
        return max(tokenScore, joinedScore)
    }

    static let stopWords: Set<String> = [
        "the", "a", "an", "my", "our", "some", "to", "with", "of", "for", "on", "up", "and", "that", "this",
        "do", "doing", "i", "i'm", "im",
    ]

    static func keyTokens(_ text: String) -> [String] {
        let words = TextNormalizer.words(TextNormalizer.normalize(text))
        let meaningful = words.filter { !stopWords.contains($0) }
        return (meaningful.isEmpty ? words : meaningful).map(stem)
    }

    /// Very small English stemmer: enough to match "dishes"/"dish", "washing"/"wash", "cleaned"/"clean".
    static func stem(_ word: String) -> String {
        var w = word
        if w.hasSuffix("'s") { w.removeLast(2) }
        for suffix in ["ing", "ies", "es", "ed", "s"] where w.count > suffix.count + 2 && w.hasSuffix(suffix) {
            w.removeLast(suffix.count)
            if suffix == "ies" { w += "y" }
            break
        }
        return w
    }

    static func tokensMatch(_ a: String, _ b: String) -> Bool {
        if a == b { return true }
        let shorter = min(a.count, b.count)
        if shorter >= 4, a.hasPrefix(b) || b.hasPrefix(a) { return true }
        guard shorter >= 4 else { return false }
        return similarity(a, b) >= 0.8
    }

    /// Normalised Levenshtein similarity in 0...1.
    static func similarity(_ a: String, _ b: String) -> Double {
        let longest = max(a.count, b.count)
        guard longest > 0 else { return 1 }
        return 1 - Double(levenshtein(Array(a), Array(b))) / Double(longest)
    }

    static func levenshtein(_ a: [Character], _ b: [Character]) -> Int {
        if a.isEmpty { return b.count }
        if b.isEmpty { return a.count }
        var previous = Array(0...b.count)
        var current = [Int](repeating: 0, count: b.count + 1)
        for i in 1...a.count {
            current[0] = i
            for j in 1...b.count {
                let cost = a[i - 1] == b[j - 1] ? 0 : 1
                current[j] = min(previous[j] + 1, current[j - 1] + 1, previous[j - 1] + cost)
            }
            swap(&previous, &current)
        }
        return previous[b.count]
    }
}
