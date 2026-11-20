import AppIntents
import Foundation

// These intents are compiled into both the app and the widget extension because widget,
// Live Activity and Control Center buttons reference them. They always run in the app process:
// LiveActivityIntent guarantees that, and openAppWhenRun launches the app.

/// The Stop button on the Live Activity / Dynamic Island. Runs without opening the app.
struct StopEntryIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Stop Timer"
    static let isDiscoverable = false

    @Parameter(title: "Entry ID")
    var entryID: String

    init() {}

    init(entryID: String) {
        self.entryID = entryID
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        if let id = UUID(uuidString: entryID) {
            await EntryService.shared.stop(entryID: id)
        } else {
            await EntryService.shared.refreshSurfaces()
        }
        return .result()
    }
}

/// Opens the app straight into listening mode. Used by the lock screen / Control Center control,
/// the "Log by voice" App Shortcut, Siri, and Back Tap (via a Shortcut).
struct LogByVoiceIntent: AppIntent {
    static let title: LocalizedStringResource = "Log by Voice"
    static let description = IntentDescription("Opens Time Tracker and starts listening, so you can say what you're starting or finishing.")
    static let openAppWhenRun: Bool = true

    init() {}

    @MainActor
    func perform() async throws -> some IntentResult {
        ListenRequest.post()
        return .result()
    }
}
