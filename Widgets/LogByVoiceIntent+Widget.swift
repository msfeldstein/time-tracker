import AppIntents
import Foundation

extension LogByVoiceIntent {
    /// LiveActivityIntent runs in the app process, so the system calls the app's `perform()`.
    /// The widget extension only declares the intent for its buttons; this is never expected to run.
    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        .result(dialog: "Open Time Tracker to log time.")
    }
}
