@preconcurrency import ActivityKit
import Foundation
import os

/// Keeps the single Live Activity in sync with the running entries.
///
/// Updates are local only (`pushType: nil`): free provisioning has no push entitlement, and
/// requesting a push token makes `Activity.request` fail on Personal Team builds. The elapsed
/// timer renders itself with `Text(_:style: .timer)`, so no periodic updates are needed.
///
/// While a Lock Screen voice capture runs, `voice` is shown on the same activity. An
/// `AudioRecordingIntent` must keep a Live Activity on screen for as long as it records.
@MainActor
enum LiveActivityManager {
    private static let logger = Logger(subsystem: "TimeTracker", category: "LiveActivity")

    /// Set while a voice intent is listening or showing its result.
    private(set) static var voice: TimerActivityAttributes.VoiceStatus?

    static var areActivitiesEnabled: Bool {
        ActivityAuthorizationInfo().areActivitiesEnabled
    }

    /// Shows (or updates) the voice status and returns whether a Live Activity is on screen.
    @discardableResult
    static func showVoice(_ status: TimerActivityAttributes.VoiceStatus, running: [RunningSnapshot]) async -> Bool {
        voice = status
        await sync(running: running)
        return Activity<TimerActivityAttributes>.activities.contains { $0.activityState == .active }
    }

    /// Goes back to showing the timers (or ends the activity if nothing is running).
    static func clearVoice(running: [RunningSnapshot]) async {
        voice = nil
        await sync(running: running)
    }

    static func sync(running: [RunningSnapshot]) async {
        let all = Activity<TimerActivityAttributes>.activities
        let live = all.filter { $0.activityState == .active || $0.activityState == .stale }
        for finished in all where !live.contains(where: { $0.id == finished.id }) {
            await finished.end(nil, dismissalPolicy: .immediate)
        }

        guard let state = state(running: running) else {
            for activity in live {
                await activity.end(nil, dismissalPolicy: .immediate)
            }
            return
        }
        let content = ActivityContent(state: state, staleDate: nil, relevanceScore: 100)

        if let current = live.first {
            if current.content.state != state {
                await current.update(content)
            }
            for extra in live.dropFirst() {
                await extra.end(nil, dismissalPolicy: .immediate)
            }
            return
        }

        guard areActivitiesEnabled else { return }
        do {
            _ = try Activity.request(attributes: TimerActivityAttributes(), content: content, pushType: nil)
        } catch {
            // Expected when the app is in the background and not running a LiveActivityIntent.
            // The next foreground refresh will create it.
            logger.info("Live Activity not started: \(error.localizedDescription, privacy: .public)")
        }
    }

    private static func state(running: [RunningSnapshot]) -> TimerActivityAttributes.ContentState? {
        guard let top = running.first else {
            guard let voice else { return nil }
            return TimerActivityAttributes.ContentState(
                entryID: "", name: "", startedAt: .distantPast, otherCount: 0, otherNames: [], voice: voice
            )
        }
        let others = running.dropFirst()
        return TimerActivityAttributes.ContentState(
            entryID: top.id.uuidString,
            name: top.name,
            startedAt: top.startedAt,
            otherCount: others.count,
            otherNames: others.prefix(3).map(\.name),
            voice: voice
        )
    }
}
