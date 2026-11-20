import AppIntents
import Foundation

// These intents are compiled into both the app and the widget extension because widget,
// Live Activity and Control Center buttons reference them. They always run in the app process
// (LiveActivityIntent guarantees that) and never open the app.
//
// Every intent here uses `authenticationPolicy = .alwaysAllowed`, so it runs from the Lock Screen
// without Face ID or the passcode. Anyone holding the phone can start, stop and log time; that's
// the deliberate trade-off (see README, "Lock Screen without unlocking").

/// The Stop button on the Live Activity / Dynamic Island. Runs without opening the app.
struct StopEntryIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Stop Timer"
    static let isDiscoverable = false
    static let authenticationPolicy: IntentAuthenticationPolicy = .alwaysAllowed

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

/// "Hey Siri, stop everything in Time Tracker", or a Shortcut. Stops every running timer.
struct StopAllActivitiesIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Stop All Activities"
    static let description = IntentDescription("Stops every activity that's running.")
    static let authenticationPolicy: IntentAuthenticationPolicy = .alwaysAllowed

    init() {}

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let outcome = await EntryService.shared.stopAllFromIntent(source: .siri)
        return .result(dialog: "\(outcome.message)")
    }
}

/// Listens and logs what she says, without opening the app and without unlocking the phone.
/// Used by the Lock Screen widget, the "Log Time" control, the "Log by Voice" App Shortcut,
/// Siri, and Back Tap (via a Shortcut).
///
/// `AudioRecordingIntent` lets it record in the background as long as a Live Activity is shown
/// ("Listening…"); `LiveActivityIntent` makes it run in the app process, which owns the speech
/// engines, and lets it start that Live Activity from the background.
///
/// `perform()` is defined per target: the app's version (App/Intents/LogByVoiceIntent+Perform.swift)
/// records; the widget extension only needs the declaration for its buttons.
struct LogByVoiceIntent: AudioRecordingIntent, LiveActivityIntent {
    static let title: LocalizedStringResource = "Log by Voice"
    static let description = IntentDescription("Listens for what you're starting or finishing and logs it. Works from the Lock Screen without unlocking.")
    static let authenticationPolicy: IntentAuthenticationPolicy = .alwaysAllowed

    init() {}
}
