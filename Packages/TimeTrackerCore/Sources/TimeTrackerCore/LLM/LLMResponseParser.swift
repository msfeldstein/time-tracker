import Foundation

/// Decodes model output. Requests use strict JSON schemas, but parsing stays tolerant: code fences,
/// extra prose, camelCase keys, numbers as strings and odd casing are all accepted, and anything
/// that doesn't map back onto the request is dropped rather than trusted.
public enum LLMResponseParser {
    public static func extractJSON(_ text: String) throws -> JSONValue {
        var body = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if body.hasPrefix("```") {
            body = body.components(separatedBy: "\n").dropFirst().joined(separator: "\n")
            if let fence = body.range(of: "```", options: .backwards) {
                body = String(body[..<fence.lowerBound])
            }
        }
        if let data = body.data(using: .utf8), let value = try? JSONDecoder().decode(JSONValue.self, from: data) {
            return value
        }
        for (open, close) in [("{", "}"), ("[", "]")] {
            if let start = body.range(of: open), let end = body.range(of: close, options: .backwards), start.lowerBound < end.lowerBound {
                let slice = String(body[start.lowerBound..<end.upperBound])
                if let data = slice.data(using: .utf8), let value = try? JSONDecoder().decode(JSONValue.self, from: data) {
                    return value
                }
            }
        }
        throw LLMServiceError.invalidResponse("No JSON found")
    }

    // MARK: Test connection

    public static func testConnection(_ text: String) throws {
        guard try extractJSON(text)["ok"]?.boolValue == true else {
            throw LLMServiceError.invalidResponse("Unexpected test reply")
        }
    }

    // MARK: Categorization

    /// Returns `[CategoryKey.normalize(activity): category]` for activities in the request only.
    public static func categories(_ text: String, for request: CategorizationRequest) throws -> [String: String] {
        let json = try extractJSON(text)
        var pairs: [(String, String)] = []
        let list = json["assignments"]?.arrayValue ?? json.arrayValue
        if let list {
            for item in list {
                guard let activity = item["activity"]?.stringValue ?? item["name"]?.stringValue,
                      let category = item["category"]?.stringValue else { continue }
                pairs.append((activity, category))
            }
        } else if case .object(let object) = json {
            // {"Dishes": "Chores"} style.
            for (activity, value) in object {
                if let category = value.stringValue { pairs.append((activity, category)) }
            }
        }
        guard !pairs.isEmpty else { throw LLMServiceError.invalidResponse("No assignments") }

        let vocabulary = request.existingCategories + CategoryDefaults.names.filter { !request.existingCategories.contains($0) }
        let wanted = request.activities
        var result: [String: String] = [:]
        for (activity, rawCategory) in pairs {
            guard let index = matchActivity(activity, in: wanted),
                  var category = CategoryKey.canonical(rawCategory, existing: vocabulary) else { continue }
            if category.caseInsensitiveCompare(CategoryDefaults.uncategorized) == .orderedSame {
                category = "Other"
            }
            let key = CategoryKey.normalize(wanted[index])
            if result[key] == nil { result[key] = category }
        }
        return result
    }

    private static func matchActivity(_ returned: String, in wanted: [String]) -> Int? {
        if let exact = wanted.firstIndex(of: returned) { return exact }
        let key = CategoryKey.normalize(returned)
        if let byKey = wanted.firstIndex(where: { CategoryKey.normalize($0) == key }) { return byKey }
        return ActivityMatcher.bestMatch(for: returned, in: wanted, threshold: 0.85)
    }

    // MARK: Interpretation

    public static func interpretation(_ text: String, for request: InterpretationRequest) throws -> InterpretationResult {
        let json = try extractJSON(text)
        guard let list = json["events"]?.arrayValue ?? json.arrayValue else {
            throw LLMServiceError.invalidResponse("No events")
        }
        let refs = Set(request.running.map(\.ref))
        var events: [InterpretedEvent] = []
        for item in list {
            let type = (item["type"]?.stringValue ?? "").lowercased()
            let text = (item["text"]?.stringValue ?? item["activity"]?.stringValue ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            switch type {
            case "start", "begin", "started", "starting":
                let name = CommandParser.cleanActivity(TextNormalizer.words(TextNormalizer.normalize(text)))
                guard !name.isEmpty else { continue }
                let minutes = min(max(item["minutes_ago"]?.intValue ?? 0, 0), 12 * 60)
                events.append(.start(activity: name, minutesAgo: minutes))
            case "stop", "end", "finish", "finished", "done":
                let ref = (item["ref"]?.stringValue ?? "").trimmingCharacters(in: .whitespaces)
                if refs.contains(ref) {
                    events.append(.stop(ref: ref))
                } else if let index = ActivityMatcher.bestMatch(for: ref.isEmpty ? text : ref, in: request.running.map(\.name), threshold: 0.8) {
                    events.append(.stop(ref: request.running[index].ref))
                }
            case "note":
                if !text.isEmpty { events.append(.note(text)) }
            default:
                continue
            }
        }
        var unique: [InterpretedEvent] = []
        for event in events where !unique.contains(event) { unique.append(event) }
        let confidence = min(max(json["confidence"]?.doubleValue ?? 0.5, 0), 1)
        return InterpretationResult(events: unique, confidence: confidence)
    }

    // MARK: Stop suggestion

    public static func stopSuggestion(_ text: String, for request: StopSuggestionRequest) throws -> StopSuggestion? {
        let json = try extractJSON(text)
        if json["has_suggestion"]?.boolValue == false { return nil }
        guard let minutes = json["minutes_after_start"]?.intValue, minutes > 0 else { return nil }
        let end = StopSuggestionHeuristics.clamp(
            request.startedAt.addingTimeInterval(TimeInterval(minutes) * 60),
            startedAt: request.startedAt,
            now: request.now
        )
        var reason = (json["reason"]?.stringValue ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if reason.isEmpty { reason = "Based on how long it usually takes" }
        if reason.count > 120 { reason = String(reason.prefix(117)) + "\u{2026}" }
        return StopSuggestion(endedAt: end, reason: reason)
    }

    // MARK: Summary

    public static func summary(_ text: String) throws -> String {
        let note: String?
        if let json = try? extractJSON(text) {
            note = json["note"]?.stringValue ?? json["summary"]?.stringValue ?? json["text"]?.stringValue ?? json.stringValue
        } else if !text.contains("{") {
            note = text
        } else {
            note = nil
        }
        guard let trimmed = note?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
            throw LLMServiceError.invalidResponse("Empty summary")
        }
        return trimmed.count > 600 ? String(trimmed.prefix(597)) + "\u{2026}" : trimmed
    }
}
