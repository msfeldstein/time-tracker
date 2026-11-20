import XCTest
import TimeTrackerCore

final class ListeningPolicyTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_000)

    func testWaitsLongerBeforeAnythingIsSaid() {
        let policy = ListeningPolicy.standard
        XCTAssertFalse(policy.shouldFinish(startedAt: start, lastTranscriptChange: start, hasTranscript: false, now: start.addingTimeInterval(5)))
        XCTAssertTrue(policy.shouldFinish(startedAt: start, lastTranscriptChange: start, hasTranscript: false, now: start.addingTimeInterval(8)))
    }

    func testFinishesAfterPauseOnceSomethingWasSaid() {
        let policy = ListeningPolicy.standard
        let spoke = start.addingTimeInterval(2)
        XCTAssertFalse(policy.shouldFinish(startedAt: start, lastTranscriptChange: spoke, hasTranscript: true, now: spoke.addingTimeInterval(1)))
        XCTAssertTrue(policy.shouldFinish(startedAt: start, lastTranscriptChange: spoke, hasTranscript: true, now: spoke.addingTimeInterval(1.6)))
    }

    func testHardLimitWinsEvenWhileTalking() {
        let policy = ListeningPolicy.locked
        let now = start.addingTimeInterval(policy.maximumDuration)
        XCTAssertTrue(policy.shouldFinish(startedAt: start, lastTranscriptChange: now, hasTranscript: true, now: now))
    }

    func testLockedLimitIsShorterThanInApp() {
        XCTAssertLessThan(ListeningPolicy.locked.maximumDuration, ListeningPolicy.standard.maximumDuration)
    }

    func testPlanHandsOffWhenAppIsOpen() {
        XCTAssertEqual(VoiceIntentPlan.decide(appIsActive: true, microphone: .notDetermined, liveActivitiesEnabled: false), .handOffToApp)
    }

    func testPlanRecordsInBackgroundWhenAllowed() {
        XCTAssertEqual(VoiceIntentPlan.decide(appIsActive: false, microphone: .granted, liveActivitiesEnabled: true), .recordInBackground)
    }

    func testPlanExplainsMissingPermissions() {
        XCTAssertEqual(VoiceIntentPlan.decide(appIsActive: false, microphone: .denied, liveActivitiesEnabled: true), .cannotRecord(.microphoneDenied))
        XCTAssertEqual(VoiceIntentPlan.decide(appIsActive: false, microphone: .notDetermined, liveActivitiesEnabled: true), .cannotRecord(.microphoneNotAsked))
        XCTAssertEqual(VoiceIntentPlan.decide(appIsActive: false, microphone: .granted, liveActivitiesEnabled: false), .cannotRecord(.liveActivitiesOff))
    }

    func testEveryProblemHasAMessage() {
        let problems: [VoiceIntentProblem] = [.microphoneDenied, .microphoneNotAsked, .liveActivitiesOff, .speechUnavailable, .nothingHeard]
        for problem in problems {
            XCTAssertFalse(problem.message.isEmpty)
        }
    }

    func testTranscriptPreviewKeepsShortText() {
        XCTAssertEqual(TranscriptPreview.tail("  starting dishes "), "starting dishes")
    }

    func testTranscriptPreviewShowsTheLatestWords() {
        let text = "done with the dishes and starting the laundry and then folding the towels before dinner"
        let preview = TranscriptPreview.tail(text, maxLength: 30)
        XCTAssertTrue(preview.hasPrefix("…"))
        XCTAssertTrue(preview.hasSuffix("before dinner"))
        XCTAssertLessThanOrEqual(preview.count, 30)
        XCTAssertFalse(preview.dropFirst().hasPrefix(" "))
    }
}
