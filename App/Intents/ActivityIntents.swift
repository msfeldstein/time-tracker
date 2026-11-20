import AppIntents
import Foundation

/// "Hey Siri, start an activity in Time Tracker" -> "What are you starting?" -> "Dishes".
///
/// Conforms to LiveActivityIntent so it runs in the app process and may start the
/// Live Activity even though the app stays in the background. Runs from the Lock Screen without
/// unlocking (`.alwaysAllowed`).
struct StartActivityIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Start Activity"
    static let description = IntentDescription("Starts timing an activity, like dishes or laundry.")
    static let authenticationPolicy: IntentAuthenticationPolicy = .alwaysAllowed

    @Parameter(title: "Activity", requestValueDialog: IntentDialog("What are you starting?"))
    var activity: String

    static var parameterSummary: some ParameterSummary {
        Summary("Start \(\.$activity)")
    }

    init() {}

    init(activity: String) {
        self.activity = activity
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let outcome = await EntryService.shared.startFromIntent(activity, source: .siri)
        return .result(dialog: "\(outcome.message)")
    }
}

/// "Hey Siri, stop timing in Time Tracker". With no activity it stops the most recent one.
struct StopActivityIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Stop Activity"
    static let description = IntentDescription("Stops an activity. Leave it empty to stop the one you started most recently.")
    static let authenticationPolicy: IntentAuthenticationPolicy = .alwaysAllowed

    @Parameter(title: "Activity")
    var activity: String?

    static var parameterSummary: some ParameterSummary {
        Summary("Stop \(\.$activity)")
    }

    init() {}

    init(activity: String?) {
        self.activity = activity
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let outcome = await EntryService.shared.stopFromIntent(activity, source: .siri)
        return .result(dialog: "\(outcome.message)")
    }
}
