@preconcurrency import ActivityKit
import Foundation
import os

/// Keeps the single Live Activity in sync with the running entries.
///
/// Updates are local only (`pushType: nil`): free provisioning has no push entitlement, and
/// requesting a push token makes `Activity.request` fail on Personal Team builds. The elapsed
/// timer renders itself with `Text(_:style: .timer)`, so no periodic updates are needed.
@MainActor
enum LiveActivityManager {
    private static let logger = Logger(subsystem: "TimeTracker", category: "LiveActivity")

    static func sync(running: [RunningSnapshot]) async {
        let all = Activity<TimerActivityAttributes>.activities
        let live = all.filter { $0.activityState == .active || $0.activityState == .stale }
        for finished in all where !live.contains(where: { $0.id == finished.id }) {
            await finished.end(nil, dismissalPolicy: .immediate)
        }

        guard let top = running.first else {
            for activity in live {
                await activity.end(nil, dismissalPolicy: .immediate)
            }
            return
        }

        let others = running.dropFirst()
        let state = TimerActivityAttributes.ContentState(
            entryID: top.id.uuidString,
            name: top.name,
            startedAt: top.startedAt,
            otherCount: others.count,
            otherNames: others.prefix(3).map(\.name)
        )
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

        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        do {
            _ = try Activity.request(attributes: TimerActivityAttributes(), content: content, pushType: nil)
        } catch {
            // Expected when the app is in the background and not running a LiveActivityIntent.
            // The next foreground refresh will create it.
            logger.info("Live Activity not started: \(error.localizedDescription, privacy: .public)")
        }
    }
}
