import Foundation

public enum ParsedCommand: Equatable, Sendable {
    case start(activity: String)
    /// `nil` means "stop the most recently started activity".
    case stop(activity: String?)
    case stopAll
    case note(String)
}

/// Deterministic, on-device parser that turns a spoken phrase into start/stop/note commands.
///
/// Handles compound phrases ("done with dishes and starting laundry"), leading filler words,
/// articles ("the dishes"), and suffix forms ("dishes are done").
public enum CommandParser {
    public static func parse(_ text: String) -> [ParsedCommand] {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        let clauses = splitIntoClauses(tokenize(trimmed))
        var commands: [ParsedCommand] = []
        for clause in clauses {
            if let command = parseClause(clause) {
                commands.append(command)
            } else if skipFillers(clause, from: 0) < clause.count {
                commands.append(.note(clause.joined(separator: " ")))
            }
        }

        let parsedSomething = commands.contains { if case .note = $0 { false } else { true } }
        if !parsedSomething {
            return [.note(trimmed)]
        }
        return commands
    }

    // MARK: - Vocabulary

    private static let boundary = "|"

    private static func phrases(_ list: [String]) -> [[String]] {
        list.map { $0.split(separator: " ").map(String.init) }
            .sorted { $0.count > $1.count }
    }

    static let startTriggers: [[String]] = phrases([
        "i'm going to start", "i am going to start", "im going to start", "i'm gonna start", "im gonna start",
        "going to start", "gonna start", "i'm about to start", "about to start", "let's start", "lets start",
        "time to start", "i'm starting", "i am starting", "im starting", "i'm beginning", "i am beginning",
        "i'm doing", "i am doing", "im doing", "i'm working on", "i am working on", "im working on", "working on",
        "i'm going to", "i am going to", "im going to", "i'm gonna", "im gonna", "going to", "gonna",
        "i'm about to", "about to", "time to", "time for", "now doing", "i started", "i'm on",
        "starting", "started", "start", "beginning", "begin", "began", "doing",
    ])

    static let stopTriggers: [[String]] = phrases([
        "i'm all done with", "i am all done with", "all done with", "i'm done with", "i am done with", "im done with",
        "i'm finished with", "i am finished with", "im finished with", "finished with", "done with",
        "i've finished", "i have finished", "i finished", "i'm through with", "i am through with", "through with",
        "i'm stopping", "i am stopping", "im stopping", "i stopped", "i'm finished", "i am finished", "im finished",
        "i'm done", "i am done", "im done", "all done", "no longer", "that's it for", "thats it for",
        "finished", "finishing", "finish", "stopping", "stopped", "stop", "ending", "ended", "end",
        "done", "completed", "complete", "quit", "quitting", "pause", "pausing",
    ])

    /// Triggers distinctive enough to start a new clause even without "and"/"then" or punctuation.
    static let strongTriggers: [[String]] = phrases([
        "starting", "i'm starting", "i am starting", "im starting", "done with", "i'm done with", "im done with",
        "finished with", "stopping", "i'm doing", "im doing", "all done with",
    ])

    static let stopSuffixes: [[String]] = phrases([
        "is done", "are done", "is finished", "are finished", "is complete", "is over", "is all done",
        "are all done", "all done", "done", "finished", "complete", "completed",
    ])

    static let connectors: Set<String> = ["and", "then", "also", "now", "plus", "so"]

    static let leadingFillers: Set<String> = [
        "okay", "ok", "um", "umm", "uh", "uhh", "er", "so", "alright", "hey", "well", "and", "then",
        "oh", "yeah", "yes", "right", "just", "also", "now", "hmm", "siri",
    ]

    static let leadingActivityNoise: Set<String> = [
        "the", "a", "an", "my", "our", "some", "to", "with", "on", "up", "of", "for", "that", "this",
    ]

    /// Only stripped when more words follow ("doing laundry" -> "laundry", but "doing" alone stays).
    static let leadingActivityVerbs: Set<String> = ["doing", "do", "working"]

    static let trailingActivityNoise: [[String]] = phrases([
        "right now", "for now", "for a bit", "for a while", "for a minute", "thank you", "the timer",
        "now", "please", "timer", "again", "thanks", "today",
    ])

    static let bareStopWords: Set<String> = [
        "it", "that", "this", "timer", "the timer", "for now", "current", "the current one", "current one",
        "what i'm doing", "what i was doing",
    ]

    static let stopAllWords: Set<String> = [
        "everything", "all", "all timers", "all of it", "all of them", "them all", "everything now",
        "for the day", "for today", "all activities", "every timer", "both", "both of them",
    ]

    // MARK: - Tokenizing and clause splitting

    private static func tokenize(_ text: String) -> [String] {
        var tokens: [String] = []
        var current = ""
        for character in text {
            if ".,;!?\n".contains(character) {
                tokens.append(contentsOf: TextNormalizer.words(TextNormalizer.normalize(current)))
                tokens.append(boundary)
                current = ""
            } else {
                current.append(character)
            }
        }
        tokens.append(contentsOf: TextNormalizer.words(TextNormalizer.normalize(current)))
        return tokens
    }

    private static func match(_ tokens: [String], at index: Int, in triggers: [[String]]) -> [String]? {
        for trigger in triggers where index + trigger.count <= tokens.count {
            if Array(tokens[index..<index + trigger.count]) == trigger {
                return trigger
            }
        }
        return nil
    }

    private static func startsCommand(_ tokens: [String], at index: Int) -> Bool {
        match(tokens, at: index, in: startTriggers) != nil || match(tokens, at: index, in: stopTriggers) != nil
    }

    private static func skipFillers(_ tokens: [String], from index: Int) -> Int {
        var i = index
        while i < tokens.count, leadingFillers.contains(tokens[i]) || tokens[i] == boundary {
            i += 1
        }
        return i
    }

    private static func splitIntoClauses(_ tokens: [String]) -> [[String]] {
        var clauses: [[String]] = []
        var current: [String] = []
        var i = 0
        while i < tokens.count {
            let token = tokens[i]
            if token == boundary {
                if !current.isEmpty {
                    clauses.append(current)
                    current = []
                }
                i += 1
                continue
            }
            if connectors.contains(token), !current.isEmpty {
                let next = skipFillers(tokens, from: i + 1)
                if next < tokens.count, startsCommand(tokens, at: next) {
                    clauses.append(current)
                    current = []
                    i = next
                    continue
                }
            }
            if !current.isEmpty, match(tokens, at: i, in: strongTriggers) != nil, !isInsideTrigger(current) {
                clauses.append(current)
                current = []
            }
            current.append(token)
            i += 1
        }
        if !current.isEmpty {
            clauses.append(current)
        }
        return clauses
    }

    /// True while `current` is only (filler +) the beginning of a trigger, e.g. ["i'm"] before "done with".
    private static func isInsideTrigger(_ current: [String]) -> Bool {
        let start = skipFillers(current, from: 0)
        if start >= current.count { return true }
        let rest = Array(current[start...])
        for trigger in startTriggers + stopTriggers where rest.count <= trigger.count {
            if Array(trigger.prefix(rest.count)) == rest { return true }
        }
        return false
    }

    // MARK: - Clause parsing

    private static func parseClause(_ clause: [String]) -> ParsedCommand? {
        let start = skipFillers(clause, from: 0)
        guard start < clause.count else { return nil }
        let words = Array(clause[start...])

        let startMatch = match(words, at: 0, in: startTriggers)
        let stopMatch = match(words, at: 0, in: stopTriggers)

        if let stopMatch, stopMatch.count >= (startMatch?.count ?? 0) {
            return stopCommand(for: Array(words.dropFirst(stopMatch.count)))
        }
        if let startMatch {
            let activity = cleanActivity(Array(words.dropFirst(startMatch.count)))
            return activity.isEmpty ? nil : .start(activity: activity)
        }
        for suffix in stopSuffixes where words.count > suffix.count {
            if Array(words.suffix(suffix.count)) == suffix {
                return stopCommand(for: Array(words.dropLast(suffix.count)))
            }
        }
        return nil
    }

    private static func stopCommand(for rest: [String]) -> ParsedCommand {
        let raw = rest.joined(separator: " ")
        if stopAllWords.contains(raw) { return .stopAll }
        if bareStopWords.contains(raw) { return .stop(activity: nil) }
        let activity = cleanActivity(rest)
        if activity.isEmpty || bareStopWords.contains(activity) { return .stop(activity: nil) }
        if stopAllWords.contains(activity) { return .stopAll }
        return .stop(activity: activity)
    }

    public static func cleanActivity(_ input: [String]) -> String {
        var words = input
        var changed = true
        while changed {
            changed = false
            if let first = words.first {
                if leadingActivityNoise.contains(first) && words.count > 1 {
                    words.removeFirst()
                    changed = true
                } else if leadingActivityVerbs.contains(first) && words.count > 1 {
                    words.removeFirst()
                    changed = true
                }
            }
            for suffix in trailingActivityNoise where words.count > suffix.count {
                if Array(words.suffix(suffix.count)) == suffix {
                    words.removeLast(suffix.count)
                    changed = true
                    break
                }
            }
        }
        if words.count == 1, leadingActivityNoise.contains(words[0]) {
            return ""
        }
        return words.joined(separator: " ")
    }
}
