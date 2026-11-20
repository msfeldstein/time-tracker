@preconcurrency import AVFoundation
import AppIntents
import Foundation
import TimeTrackerCore
import UIKit
import os

extension LogByVoiceIntent {
    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let message = await LockedVoiceCapture.run()
        return .result(dialog: IntentDialog(stringLiteral: message))
    }
}

/// Voice capture for `LogByVoiceIntent`, which runs in the background, usually from the Lock
/// Screen. It shows a "Listening…" Live Activity (required by `AudioRecordingIntent` for the whole
/// recording), listens with the same on-device engines and silence rules as the in-app mic, then
/// saves exactly like the app: raw transcript first (`EntryService.capture`), then interpretation.
@MainActor
enum LockedVoiceCapture {
    private static let logger = Logger(subsystem: "TimeTracker", category: "LockedVoice")
    private static var isRunning = false
    /// How long "Got it · Started Dishes" stays on the Live Activity.
    private static let resultDisplay: Duration = .seconds(3)

    /// Returns what happened, for Siri or Shortcuts to say.
    static func run() async -> String {
        let plan = VoiceIntentPlan.decide(
            appIsActive: UIApplication.shared.applicationState == .active,
            microphone: microphonePermission,
            liveActivitiesEnabled: LiveActivityManager.areActivitiesEnabled
        )
        switch plan {
        case .handOffToApp:
            // The app is on screen (so the phone is unlocked): use the normal mic UI.
            ListenRequest.post()
            return "Listening…"
        case .cannotRecord(let problem):
            return problem.message
        case .recordInBackground:
            break
        }

        guard !isRunning else { return "Already listening." }
        isRunning = true
        defer { isRunning = false }

        let service = EntryService.shared
        // Any transcript left over from an interrupted session is finished first.
        await service.reprocessPendingCaptures()

        let shown = await LiveActivityManager.showVoice(.init(phase: .listening, text: ""), running: snapshots())
        guard shown else {
            await LiveActivityManager.clearVoice(running: snapshots())
            return VoiceIntentProblem.liveActivitiesOff.message
        }

        let controller = VoiceCaptureController(
            policy: .locked,
            allowsPermissionPrompts: false,
            source: .voice,
            nothingHeardMessage: VoiceIntentProblem.nothingHeard.message
        )
        controller.start()
        let result = await follow(controller)

        await LiveActivityManager.showVoice(result, running: snapshots())
        try? await Task.sleep(for: resultDisplay)
        await LiveActivityManager.clearVoice(running: snapshots())
        return result.text
    }

    /// Mirrors the controller's progress onto the Live Activity until it's done.
    private static func follow(_ controller: VoiceCaptureController) async -> TimerActivityAttributes.VoiceStatus {
        let deadline = Date().addingTimeInterval(controller.policy.maximumDuration + 20)
        var shownText = ""
        var shownPhase = TimerActivityAttributes.VoiceStatus.Phase.listening
        var lastUpdate = Date.distantPast

        while true {
            switch controller.phase {
            case .done(let message):
                return .init(phase: .done, text: message)
            case .failed(let message):
                logger.info("Lock Screen capture failed: \(message, privacy: .public)")
                return .init(phase: .failed, text: message)
            case .idle:
                return .init(phase: .failed, text: VoiceIntentProblem.nothingHeard.message)
            case .preparing, .listening, .saving:
                break
            }

            if Date() > deadline, controller.phase == .listening {
                // Safety net; the controller's own time limit normally ends listening first.
                controller.finish()
            }

            let phase: TimerActivityAttributes.VoiceStatus.Phase = controller.phase == .saving ? .saving : .listening
            let text = TranscriptPreview.tail(controller.transcript)
            // Live Activity updates are rate-limited by iOS, so send at most about two a second.
            if (text != shownText || phase != shownPhase), Date().timeIntervalSince(lastUpdate) >= 0.5 {
                shownText = text
                shownPhase = phase
                lastUpdate = Date()
                await LiveActivityManager.showVoice(.init(phase: phase, text: text), running: snapshots())
            }
            try? await Task.sleep(for: .milliseconds(150))
        }
    }

    private static var microphonePermission: PermissionState {
        switch AVAudioApplication.shared.recordPermission {
        case .granted: .granted
        case .denied: .denied
        default: .notDetermined
        }
    }

    private static func snapshots() -> [RunningSnapshot] {
        EntryService.shared.runningEntries().map(RunningSnapshot.init)
    }
}
