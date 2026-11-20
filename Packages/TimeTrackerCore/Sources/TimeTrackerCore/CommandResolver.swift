import Foundation

public struct RunningActivity: Equatable, Sendable {
    public let id: UUID
    public let name: String
    public let startedAt: Date

    public init(id: UUID, name: String, startedAt: Date) {
        self.id = id
        self.name = name
        self.startedAt = startedAt
    }
}

public enum PlannedAction: Equatable, Sendable {
    case start(name: String)
    case stop(id: UUID)
    case note(text: String)
    /// "starting dishes" while Dishes is already running: nothing changes.
    case alreadyRunning(id: UUID)
    /// "done with taxes" when nothing like it is running: the text is still kept as a note.
    case noMatch(query: String, text: String)
    /// "stop" when nothing is running.
    case nothingRunning
}

public struct Resolution: Equatable, Sendable {
    public let actions: [PlannedAction]
    /// Stops chosen by a weak or ambiguous fuzzy match; worth a second opinion from the LLM.
    public let lowConfidenceStops: [UUID]
}

/// Turns parsed commands into concrete actions against the currently running activities.
/// Pure logic so it can be unit tested without SwiftData.
public enum CommandResolver {
    public static func resolve(
        _ commands: [ParsedCommand],
        running: [RunningActivity],
        rawText: String
    ) -> [PlannedAction] {
        resolveWithConfidence(commands, running: running, rawText: rawText).actions
    }

    public static func resolveWithConfidence(
        _ commands: [ParsedCommand],
        running: [RunningActivity],
        rawText: String
    ) -> Resolution {
        var open = running.sorted { $0.startedAt > $1.startedAt }
        var actions: [PlannedAction] = []
        var lowConfidence: [UUID] = []

        func stop(at index: Int) {
            actions.append(.stop(id: open[index].id))
            open.remove(at: index)
        }

        for command in commands {
            switch command {
            case .start(let activity):
                let name = TextNormalizer.displayName(activity)
                if let existing = open.first(where: { ActivityMatcher.score($0.name, name) >= 0.99 }) {
                    actions.append(.alreadyRunning(id: existing.id))
                } else {
                    actions.append(.start(name: name))
                }

            case .stop(nil):
                if open.isEmpty {
                    actions.append(.nothingRunning)
                } else {
                    stop(at: 0)
                }

            case .stop(let query?):
                // "dishes and laundry" stops both, but only when each part names a different
                // running activity, so an activity called "mac and cheese" still matches whole.
                let names = open.map(\.name)
                let parts = query.components(separatedBy: " and ").filter { !$0.isEmpty }
                let partIndexes = parts.compactMap { ActivityMatcher.bestMatch(for: $0, in: names) }
                if parts.count > 1, partIndexes.count == parts.count, Set(partIndexes).count == parts.count {
                    let ids = partIndexes.map { open[$0].id }
                    for id in ids {
                        if let index = open.firstIndex(where: { $0.id == id }) { stop(at: index) }
                    }
                } else if let index = ActivityMatcher.bestMatch(for: query, in: names) {
                    if ActivityMatcher.isLowConfidence(query: query, chosen: index, in: names) {
                        lowConfidence.append(open[index].id)
                    }
                    stop(at: index)
                } else {
                    actions.append(.noMatch(query: query, text: rawText))
                }

            case .stopAll:
                if open.isEmpty {
                    actions.append(.nothingRunning)
                }
                while !open.isEmpty { stop(at: 0) }

            case .note(let text):
                actions.append(.note(text: text))
            }
        }
        return Resolution(actions: actions, lowConfidenceStops: lowConfidence)
    }
}
