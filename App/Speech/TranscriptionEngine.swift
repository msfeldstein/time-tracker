@preconcurrency import AVFoundation
import Foundation

/// A speech-to-text engine. All implementations run entirely on device.
protocol TranscriptionEngine: AnyObject, Sendable {
    var displayName: String { get }
    /// Starts the microphone and transcription. `onText` receives the whole transcript so far, on any thread.
    func start(onText: @escaping @Sendable (String) -> Void) async throws
    /// Stops listening and waits (briefly) for the final transcript to be delivered through `onText`.
    func finish() async
    /// Stops immediately, discarding pending results.
    func cancel() async
}

enum SpeechCaptureError: LocalizedError {
    case microphoneDenied
    case speechDenied
    case noMicrophone
    case onDeviceUnavailable
    case localeUnsupported

    var errorDescription: String? {
        switch self {
        case .microphoneDenied:
            "Time Tracker needs the microphone. Turn it on in Settings › Apps › Time Tracker."
        case .speechDenied:
            "Speech recognition is turned off. Turn it on in Settings › Apps › Time Tracker."
        case .noMicrophone:
            "No microphone is available right now."
        case .onDeviceUnavailable:
            "On-device speech recognition isn't available for your language yet. Check Settings › General › Keyboard › Dictation."
        case .localeUnsupported:
            "Your language isn't supported for on-device transcription."
        }
    }
}

enum TranscriptionEngines {
    /// Preferred engine first. Both are on-device only; audio never leaves the phone.
    static func candidates() -> [any TranscriptionEngine] {
        [SpeechAnalyzerEngine(), LegacySpeechEngine()]
    }
}

/// Microphone plumbing shared by both engines. Installed from nonisolated code so the tap block
/// (called on the real-time audio thread) never inherits main-actor isolation.
final class MicrophoneTap: @unchecked Sendable {
    private let engine = AVAudioEngine()

    func start(bufferSize: AVAudioFrameCount = 4096, handler: @escaping @Sendable (AVAudioPCMBuffer) -> Void) throws -> AVAudioFormat {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.record, mode: .measurement, options: [.duckOthers])
        try session.setActive(true, options: .notifyOthersOnDeactivation)

        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else {
            throw SpeechCaptureError.noMicrophone
        }
        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: bufferSize, format: format, block: Self.tapBlock(handler))
        engine.prepare()
        try engine.start()
        return format
    }

    func stop() {
        engine.inputNode.removeTap(onBus: 0)
        if engine.isRunning {
            engine.stop()
        }
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    private nonisolated static func tapBlock(_ handler: @escaping @Sendable (AVAudioPCMBuffer) -> Void) -> AVAudioNodeTapBlock {
        { buffer, _ in handler(buffer) }
    }
}
