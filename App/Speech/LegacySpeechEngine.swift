@preconcurrency import AVFoundation
import Foundation
@preconcurrency import Speech

/// Fallback for devices or languages where SpeechTranscriber isn't available.
/// `requiresOnDeviceRecognition` guarantees audio is never sent to Apple's servers; if the
/// device can't recognize on-device, this engine refuses to start rather than going online.
final class LegacySpeechEngine: TranscriptionEngine, @unchecked Sendable {
    let displayName = "SFSpeechRecognizer (on-device)"

    private let microphone = MicrophoneTap()
    private let lock = NSLock()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var isFinished = false

    func start(onText: @escaping @Sendable (String) -> Void) async throws {
        let status = await withCheckedContinuation { (continuation: CheckedContinuation<SFSpeechRecognizerAuthorizationStatus, Never>) in
            SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0) }
        }
        guard status == .authorized else { throw SpeechCaptureError.speechDenied }

        guard let recognizer = SFSpeechRecognizer(locale: Locale.current) ?? SFSpeechRecognizer(locale: Locale(identifier: "en-US")),
              recognizer.isAvailable else {
            throw SpeechCaptureError.localeUnsupported
        }
        guard recognizer.supportsOnDeviceRecognition else {
            throw SpeechCaptureError.onDeviceUnavailable
        }

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.requiresOnDeviceRecognition = true
        request.shouldReportPartialResults = true
        request.taskHint = .dictation
        request.addsPunctuation = true

        lock.withLock {
            self.request = request
            self.isFinished = false
        }

        let task = recognizer.recognitionTask(with: request) { [weak self] result, error in
            if let result {
                onText(result.bestTranscription.formattedString)
            }
            if error != nil || result?.isFinal == true {
                self?.markFinished()
            }
        }
        lock.withLock { self.task = task }

        nonisolated(unsafe) let audioRequest = request
        do {
            _ = try microphone.start { buffer in audioRequest.append(buffer) }
        } catch {
            await cancel()
            throw error
        }
    }

    private func markFinished() {
        lock.withLock { isFinished = true }
    }

    func finish() async {
        microphone.stop()
        let request = lock.withLock { self.request }
        request?.endAudio()
        // Wait up to ~2 seconds for the final result.
        for _ in 0..<40 {
            if lock.withLock({ isFinished }) { break }
            try? await Task.sleep(for: .milliseconds(50))
        }
        lock.withLock {
            task?.finish()
            task = nil
            self.request = nil
        }
    }

    func cancel() async {
        microphone.stop()
        lock.withLock {
            request?.endAudio()
            task?.cancel()
            task = nil
            request = nil
        }
    }
}
