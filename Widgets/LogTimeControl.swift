import AppIntents
import SwiftUI
import WidgetKit

/// Control Center / Lock Screen control (iOS 18+) that opens the app in listening mode.
/// Also assignable to the Action button on newer iPhones.
struct LogTimeControl: ControlWidget {
    static let kind = "LogTimeControl"

    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: Self.kind) {
            ControlWidgetButton(action: LogByVoiceIntent()) {
                Label("Log Time", systemImage: "mic.fill")
            }
        }
        .displayName("Log Time")
        .description("Open Time Tracker and start listening.")
    }
}
