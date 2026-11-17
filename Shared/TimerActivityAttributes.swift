import ActivityKit
import Foundation

/// One Live Activity represents everything that's running: the most recently started
/// activity is shown with its timer, plus a count of the others.
struct TimerActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable, Sendable {
        var entryID: String
        var name: String
        var startedAt: Date
        var otherCount: Int
        var otherNames: [String]
    }
}
