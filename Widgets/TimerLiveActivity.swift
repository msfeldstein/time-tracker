import ActivityKit
import AppIntents
import SwiftUI
import WidgetKit

/// Lock Screen Live Activity and Dynamic Island (the iPhone 13 mini has no Dynamic Island,
/// so there it appears on the Lock Screen and as a banner).
struct TimerLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: TimerActivityAttributes.self) { context in
            LockScreenLiveActivityView(state: context.state)
                .activityBackgroundTint(Color.black.opacity(0.55))
                .activitySystemActionForegroundColor(.white)
                .widgetURL(AppConfig.homeURL)
        } dynamicIsland: { context in
            let state = context.state
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Label {
                        Text(state.name).lineLimit(1)
                    } icon: {
                        Image(systemName: "timer")
                    }
                    .font(.headline)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text(state.startedAt, style: .timer)
                        .font(.title3.weight(.semibold).monospacedDigit())
                        .multilineTextAlignment(.trailing)
                        .frame(maxWidth: 90)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    HStack {
                        if state.otherCount > 0 {
                            Text("+\(state.otherCount) more running")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        StopButton(entryID: state.entryID)
                    }
                }
            } compactLeading: {
                HStack(spacing: 2) {
                    Image(systemName: "timer")
                    if state.otherCount > 0 {
                        Text("\(state.otherCount + 1)").font(.caption2.bold())
                    }
                }
                .foregroundStyle(.orange)
            } compactTrailing: {
                Text(state.startedAt, style: .timer)
                    .monospacedDigit()
                    .frame(maxWidth: 52)
            } minimal: {
                Image(systemName: "timer")
                    .foregroundStyle(.orange)
            }
            .widgetURL(AppConfig.homeURL)
        }
    }
}

private struct LockScreenLiveActivityView: View {
    let state: TimerActivityAttributes.ContentState

    var body: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Text(state.name)
                    .font(.title3.weight(.semibold))
                    .lineLimit(1)
                Text(state.startedAt, style: .timer)
                    .font(.largeTitle.weight(.bold).monospacedDigit())
                if state.otherCount > 0 {
                    Text(othersText)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 8)
            StopButton(entryID: state.entryID)
        }
        .foregroundStyle(.white)
        .padding(16)
    }

    private var othersText: String {
        let names = state.otherNames.joined(separator: ", ")
        let extra = state.otherCount - state.otherNames.count
        return "Also: " + names + (extra > 0 ? " +\(extra)" : "")
    }
}

private struct StopButton: View {
    let entryID: String

    var body: some View {
        Button(intent: StopEntryIntent(entryID: entryID)) {
            Label("Stop", systemImage: "stop.fill")
                .font(.headline)
                .padding(.horizontal, 6)
                .padding(.vertical, 4)
        }
        .buttonStyle(.borderedProminent)
        .tint(.red)
    }
}
