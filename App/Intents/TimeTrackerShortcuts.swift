import AppIntents

/// Siri phrases available as soon as the app is installed. Every phrase must contain the app name.
/// String parameters can't be part of a phrase, so Siri asks "What are you starting?" as a follow-up.
struct TimeTrackerShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: LogByVoiceIntent(),
            phrases: [
                "Log time in \(.applicationName)",
                "Log by voice in \(.applicationName)",
                "Open \(.applicationName) and listen",
                "\(.applicationName) listen",
            ],
            shortTitle: "Log by Voice",
            systemImageName: "mic.fill"
        )
        AppShortcut(
            intent: StartActivityIntent(),
            phrases: [
                "Start an activity in \(.applicationName)",
                "Start timing in \(.applicationName)",
                "Start a timer in \(.applicationName)",
                "\(.applicationName) start",
            ],
            shortTitle: "Start Activity",
            systemImageName: "play.circle.fill"
        )
        AppShortcut(
            intent: StopActivityIntent(),
            phrases: [
                "Stop timing in \(.applicationName)",
                "Stop my activity in \(.applicationName)",
                "I'm done in \(.applicationName)",
                "\(.applicationName) stop",
            ],
            shortTitle: "Stop Activity",
            systemImageName: "stop.circle.fill"
        )
    }
}
