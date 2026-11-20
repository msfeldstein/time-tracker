import Foundation

/// When a listening session should end by itself: after a pause once something was said,
/// after a longer wait if nothing is heard at all, or at a hard time limit.
public struct ListeningPolicy: Sendable, Equatable {
    /// Stop after this much quiet once she has said something.
    public var silenceAfterSpeech: TimeInterval
    /// Give up if nothing at all is heard for this long.
    public var silenceBeforeSpeech: TimeInterval
    public var maximumDuration: TimeInterval

    public init(silenceAfterSpeech: TimeInterval = 1.6, silenceBeforeSpeech: TimeInterval = 8, maximumDuration: TimeInterval = 45) {
        self.silenceAfterSpeech = silenceAfterSpeech
        self.silenceBeforeSpeech = silenceBeforeSpeech
        self.maximumDuration = maximumDuration
    }

    /// In-app listening.
    public static let standard = ListeningPolicy()

    /// Lock Screen, Siri and Back Tap: there is no button to tap to finish, and the intent
    /// has a limited time to run, so the limits are a little tighter.
    public static let locked = ListeningPolicy(silenceAfterSpeech: 1.8, silenceBeforeSpeech: 7, maximumDuration: 25)

    public func shouldFinish(startedAt: Date, lastTranscriptChange: Date, hasTranscript: Bool, now: Date) -> Bool {
        if now.timeIntervalSince(startedAt) >= maximumDuration { return true }
        if !hasTranscript {
            return now.timeIntervalSince(startedAt) >= silenceBeforeSpeech
        }
        return now.timeIntervalSince(lastTranscriptChange) >= silenceAfterSpeech
    }
}

/// Decides how the "Log Time" voice intent should run, before touching the microphone.
/// Recording in the background is only allowed with permissions already granted (iOS can't
/// show a permission prompt on the Lock Screen) and with a Live Activity on screen.
public enum VoiceIntentPlan: Equatable, Sendable {
    /// The app is open: let the in-app mic handle it.
    case handOffToApp
    /// Record in the background with a "Listening..." Live Activity.
    case recordInBackground
    /// Can't record: tell her what to do instead.
    case cannotRecord(VoiceIntentProblem)

    public static func decide(appIsActive: Bool, microphone: PermissionState, liveActivitiesEnabled: Bool) -> VoiceIntentPlan {
        if appIsActive { return .handOffToApp }
        switch microphone {
        case .denied: return .cannotRecord(.microphoneDenied)
        case .notDetermined: return .cannotRecord(.microphoneNotAsked)
        case .granted: break
        }
        guard liveActivitiesEnabled else { return .cannotRecord(.liveActivitiesOff) }
        return .recordInBackground
    }
}

public enum PermissionState: Sendable, Equatable {
    case granted
    case denied
    case notDetermined
}

public enum VoiceIntentProblem: Sendable, Equatable {
    case microphoneDenied
    case microphoneNotAsked
    case liveActivitiesOff
    case speechUnavailable
    case nothingHeard

    /// Spoken by Siri / shown by Shortcuts. Every message says what to do next.
    public var message: String {
        switch self {
        case .microphoneDenied:
            "Time Tracker can't use the microphone. Turn it on in Settings › Apps › Time Tracker, or open the app to log time."
        case .microphoneNotAsked:
            "Open Time Tracker once and allow the microphone, then this works from the Lock Screen."
        case .liveActivitiesOff:
            "Listening from the Lock Screen needs Live Activities. Turn them on in Settings › Apps › Time Tracker, or open the app to log time."
        case .speechUnavailable:
            "Speech recognition isn't ready right now. Open Time Tracker to log time."
        case .nothingHeard:
            "I didn't catch that. Try again."
        }
    }
}

public enum TranscriptPreview {
    /// The end of a long transcript, so the Lock Screen always shows the latest words.
    public static func tail(_ text: String, maxLength: Int = 80) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard maxLength > 1, trimmed.count > maxLength else { return trimmed }
        let suffix = trimmed.suffix(maxLength - 1)
        // Start at a word boundary when there is one.
        if let space = suffix.firstIndex(of: " "), suffix.distance(from: suffix.startIndex, to: space) < maxLength / 3 {
            return "…" + suffix[suffix.index(after: space)...]
        }
        return "…" + suffix
    }
}
