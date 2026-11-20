import AppIntents
import SwiftUI
import WidgetKit

/// Control Center / Lock Screen control (iOS 18+) that listens and logs by voice without
/// unlocking or opening the app (`LogByVoiceIntent`, a "Listening…" Live Activity shows while
/// it records). Also assignable to the Action button on newer iPhones.
struct LogTimeControl: ControlWidget {
    static let kind = "LogTimeControl"

    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: Self.kind) {
            ControlWidgetButton(action: LogByVoiceIntent()) {
                Label("Log Time", systemImage: "mic.fill")
            }
        }
        .displayName("Log Time")
        .description("Say what you're starting or finishing. Works without unlocking.")
    }
}
