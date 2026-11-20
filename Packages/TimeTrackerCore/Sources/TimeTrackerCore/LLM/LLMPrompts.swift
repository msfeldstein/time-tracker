import Foundation

public struct LLMPrompt: Sendable, Equatable {
    public let system: String
    public let user: String
    public let schema: JSONValue
    public let maxTokens: Int
}

/// Builds the prompts and strict JSON schemas sent to Claude. Only activity text, times and
/// categories go in; never audio or identifiers from the database.
public struct LLMPrompts: Sendable {
    public let timeZone: TimeZone

    public init(timeZone: TimeZone = .current) {
        self.timeZone = timeZone
    }

    // MARK: Test

    public func testConnection() -> LLMPrompt {
        LLMPrompt(
            system: "You are a connectivity check. Reply with ok set to true.",
            user: "Ping.",
            schema: JSONSchema.object(["ok": JSONSchema.boolean()]),
            maxTokens: 256
        )
    }

    // MARK: Categorization

    public static let categorizationSchema = JSONSchema.object([
        "assignments": JSONSchema.array(of: JSONSchema.object([
            "activity": JSONSchema.string("The activity text, copied exactly"),
            "category": JSONSchema.string("One or two words, Title Case"),
        ])),
    ])

    public func categorize(_ request: CategorizationRequest) -> LLMPrompt {
        let existing = request.existingCategories.isEmpty ? CategoryDefaults.names : request.existingCategories
        let system = """
        You sort one person's everyday activities into a small, stable set of life categories for her personal time tracker.
        Rules:
        - Reuse one of the existing categories whenever it reasonably fits. Spell it exactly as given.
        - Only invent a new category when none fit; use one or two plain words in Title Case.
        - Never answer "\(CategoryDefaults.uncategorized)". Use "Other" if nothing fits.
        - Return exactly one assignment per activity, copying the activity text exactly.
        """
        let user = """
        Existing categories: \(existing.joined(separator: ", "))

        Activities:
        \(request.activities.map { "- \($0)" }.joined(separator: "\n"))
        """
        return LLMPrompt(system: system, user: user, schema: Self.categorizationSchema, maxTokens: 2048)
    }

    // MARK: Interpretation

    public static let interpretationSchema = JSONSchema.object([
        "events": JSONSchema.array(of: JSONSchema.object([
            "type": JSONSchema.enumeration(["start", "stop", "note"]),
            "text": JSONSchema.string("start: short activity name; note: the note text; stop: empty"),
            "ref": JSONSchema.string("stop: the ref of the running activity; otherwise empty"),
            "minutes_ago": JSONSchema.integer("How long ago it happened if she said so, else 0"),
        ])),
        "confidence": JSONSchema.number("0 to 1, how sure you are about the whole interpretation"),
    ])

    public func interpret(_ request: InterpretationRequest) -> LLMPrompt {
        let system = """
        You turn a short voice note from a personal time tracker into start and stop events.
        She says things like "starting dishes", "done with the laundry", or "picking up the kids then groceries".
        Event types:
        - start: she is beginning an activity. text is a short activity name (1 to 4 words, lower case unless a proper noun), without filler like "the" or "now".
        - stop: she finished one of the running activities. ref is that activity's ref. Pick the one she most likely means.
        - note: anything that is not starting or stopping an activity. text is the note.
        Never invent activities she didn't mention. If she only mentions finishing, don't add a start.
        minutes_ago is how long ago the event happened if she says so (e.g. "I started laundry 20 minutes ago" gives 20), otherwise 0.
        confidence is between 0 and 1 for the whole interpretation; use a low value if the note is unclear.
        """
        let running = request.running.isEmpty
            ? "Running activities: none"
            : "Running activities:\n" + request.running
                .map { "- \($0.ref): \($0.name) (started \(time($0.startedAt)))" }
                .joined(separator: "\n")
        let user = """
        Spoken at: \(dateTime(request.spokenAt)) (time zone \(timeZone.identifier))
        \(running)

        Voice note: \(quoted(request.transcript))
        """
        return LLMPrompt(system: system, user: user, schema: Self.interpretationSchema, maxTokens: 2048)
    }

    // MARK: Stop suggestion

    public static let stopSuggestionSchema = JSONSchema.object([
        "has_suggestion": JSONSchema.boolean(),
        "minutes_after_start": JSONSchema.integer("When it most likely ended, in minutes after it started"),
        "reason": JSONSchema.string("Short and friendly, under 12 words"),
    ])

    public func suggestStop(_ request: StopSuggestionRequest) -> LLMPrompt {
        let system = """
        You help one person fix a timer she forgot to stop in her personal time tracker.
        Suggest when the activity most likely really ended, using how long it usually takes and what she started afterwards.
        Be realistic and conservative. Answer in whole minutes after the start time.
        If there's no reasonable basis for a guess, set has_suggestion to false.
        """
        var lines = [
            "Activity: \(request.activity)" + (request.category.map { " (category: \($0))" } ?? ""),
            "Started: \(dateTime(request.startedAt))",
            "Now: \(dateTime(request.now)) (still running, \(Int(request.now.timeIntervalSince(request.startedAt) / 60)) minutes so far)",
            "Time zone: \(timeZone.identifier)",
        ]
        if let typical = request.typicalMinutes {
            lines.append("Usual length: about \(typical) minutes")
        }
        lines.append(request.history.isEmpty
            ? "Past sessions of this activity: none"
            : "Past sessions of this activity:\n" + request.history
                .map { "- \(dateTime($0.startedAt)), \($0.minutes) min" }
                .joined(separator: "\n"))
        if !request.laterActivities.isEmpty {
            lines.append("Started after it:\n" + request.laterActivities
                .map { "- \(time($0.startedAt))" + ($0.minutes > 0 ? ", \($0.minutes) min" : "") }
                .joined(separator: "\n"))
        }
        return LLMPrompt(system: system, user: lines.joined(separator: "\n"), schema: Self.stopSuggestionSchema, maxTokens: 1024)
    }

    // MARK: Summary

    public static let summarySchema = JSONSchema.object([
        "note": JSONSchema.string("2 or 3 short sentences, under 60 words"),
    ])

    public func summarize(_ request: SummaryRequest) -> LLMPrompt {
        let system = """
        You write a short, warm, plain-language note for one person about how she spent her time, from her personal time tracker.
        2 or 3 short sentences, under 60 words. Speak to her as "you".
        Be friendly and encouraging, never judgmental. No advice unless it's gentle, no emojis, no lists, no headings.
        Round times naturally ("about 2 hours"). Only mention what's in the data.
        """
        let totals = request.totals.isEmpty
            ? "Nothing tracked."
            : request.totals.map { "- \($0.category): \(DurationFormatting.short($0.seconds))" }.joined(separator: "\n")
        let activities = request.topActivities
            .map { "- \($0.name) (\($0.category)): \(DurationFormatting.short($0.seconds)), \($0.sessions == 1 ? "once" : "\($0.sessions) times")" }
            .joined(separator: "\n")
        let user = """
        Period: \(request.periodLabel)
        Time by category:
        \(totals)
        Top activities:
        \(activities.isEmpty ? "none" : activities)
        """
        return LLMPrompt(system: system, user: user, schema: Self.summarySchema, maxTokens: 1024)
    }

    // MARK: Formatting

    func dateTime(_ date: Date) -> String {
        formatter("EEE yyyy-MM-dd HH:mm").string(from: date)
    }

    func time(_ date: Date) -> String {
        formatter("HH:mm").string(from: date)
    }

    private func formatter(_ format: String) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = format
        return formatter
    }

    private func quoted(_ text: String) -> String {
        "\u{201C}" + text.replacingOccurrences(of: "\n", with: " ") + "\u{201D}"
    }
}
