import ActivityKit
import AppIntents
import SwiftUI
import WidgetKit

/// Lock Screen Live Activity and Dynamic Island (the iPhone 13 mini has no Dynamic Island,
/// so there it appears on the Lock Screen and as a banner).
struct TimerLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: TimerActivityAttributes.self) { context in
            Group {
                if let voice = context.state.voice {
                    VoiceLiveActivityView(voice: voice)
                } else {
                    LockScreenLiveActivityView(state: context.state)
                }
            }
                .activityBackgroundTint(Color.black.opacity(0.55))
                .activitySystemActionForegroundColor(.white)
                .widgetURL(AppConfig.homeURL)
        } dynamicIsland: { context in
            let state = context.state
            if let voice = state.voice {
                return Self.voiceIsland(voice)
            }
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

    private static func voiceIsland(_ voice: TimerActivityAttributes.VoiceStatus) -> DynamicIsland {
        DynamicIsland {
            DynamicIslandExpandedRegion(.leading) {
                Image(systemName: voice.symbol)
                    .font(.title2)
                    .foregroundStyle(voice.tint)
            }
            DynamicIslandExpandedRegion(.center) {
                Text(voice.title)
                    .font(.headline)
            }
            DynamicIslandExpandedRegion(.bottom) {
                if !voice.text.isEmpty {
                    Text(voice.text)
                        .font(.subheadline)
                        .lineLimit(2)
                }
            }
        } compactLeading: {
            Image(systemName: voice.symbol)
                .foregroundStyle(voice.tint)
        } compactTrailing: {
            Text(voice.title)
                .font(.caption2)
                .lineLimit(1)
                .frame(maxWidth: 72)
        } minimal: {
            Image(systemName: voice.symbol)
                .foregroundStyle(voice.tint)
        }
        .widgetURL(AppConfig.homeURL)
    }
}

/// "Listening…" while she logs by voice from the Lock Screen, then what happened.
private struct VoiceLiveActivityView: View {
    let voice: TimerActivityAttributes.VoiceStatus

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: voice.symbol)
                .font(.system(size: 30, weight: .semibold))
                .foregroundStyle(voice.tint)
                .symbolEffect(.pulse, isActive: voice.phase == .listening)
                .frame(width: 44)
            VStack(alignment: .leading, spacing: 2) {
                Text(voice.title)
                    .font(.title3.weight(.semibold))
                if !voice.text.isEmpty {
                    Text(voice.text)
                        .font(.body)
                        .lineLimit(3)
                        .foregroundStyle(voice.phase == .listening ? .secondary : .primary)
                }
            }
            Spacer(minLength: 0)
        }
        .foregroundStyle(.white)
        .padding(16)
    }
}

private extension TimerActivityAttributes.VoiceStatus {
    var title: String {
        switch phase {
        case .listening: "Listening…"
        case .saving: "Saving…"
        case .done: "Got it"
        case .failed: "Didn't log"
        }
    }

    var symbol: String {
        switch phase {
        case .listening: "mic.fill"
        case .saving: "waveform"
        case .done: "checkmark.circle.fill"
        case .failed: "exclamationmark.circle.fill"
        }
    }

    var tint: Color {
        switch phase {
        case .listening, .saving: .orange
        case .done: .green
        case .failed: .yellow
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
