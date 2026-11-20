import SwiftUI
import WidgetKit

@main
struct TimeTrackerWidgetBundle: WidgetBundle {
    var body: some Widget {
        RunningActivityWidget()
        TimerLiveActivity()
        LogTimeControl()
    }
}
