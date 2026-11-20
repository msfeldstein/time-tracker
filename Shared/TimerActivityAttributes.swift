import ActivityKit
import Foundation

/// One Live Activity represents everything that's running: the most recently started
/// activity is shown with its timer, plus a count of the others. While she logs by voice
/// from the Lock Screen it shows "Listening…" instead (`voice` is set).
struct TimerActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable, Sendable {
        /// Empty when nothing is running (only possible while `voice` is set).
        var entryID: String
        var name: String
        var startedAt: Date
        var otherCount: Int
        var otherNames: [String]
        /// Optional so activities started by an older build still decode.
        var voice: VoiceStatus?

        var hasTimer: Bool { !entryID.isEmpty }
    }

    /// Voice capture running from an App Intent (Lock Screen widget, control, Siri, Back Tap).
    struct VoiceStatus: Codable, Hashable, Sendable {
        enum Phase: String, Codable, Sendable {
            case listening
            case saving
            case done
            case failed
        }

        var phase: Phase
        /// The live transcript while listening, then the outcome ("Started Dishes").
        var text: String
    }
}
