@preconcurrency import AVFoundation
import Foundation
@preconcurrency import Speech

/// iOS 26 SpeechAnalyzer + SpeechTranscriber. Always on device; the language model is
/// downloaded once by the system if it isn't installed yet.
final class SpeechAnalyzerEngine: TranscriptionEngine, @unchecked Sendable {
    let displayName = "SpeechAnalyzer (on-device)"

    private let microphone = MicrophoneTap()
    private let lock = NSLock()
    private var analyzer: SpeechAnalyzer?
    private var inputContinuation: AsyncStream<AnalyzerInput>.Continuation?
    private var resultsTask: Task<Void, Never>?

    func start(onText: @escaping @Sendable (String) -> Void) async throws {
        guard SpeechTranscriber.isAvailable else {
            throw SpeechCaptureError.onDeviceUnavailable
        }
        guard let locale = await SpeechTranscriber.supportedLocale(equivalentTo: Locale.current) else {
            throw SpeechCaptureError.localeUnsupported
        }

        let transcriber = SpeechTranscriber(
            locale: locale,
            transcriptionOptions: [],
            reportingOptions: [.volatileResults],
            attributeOptions: []
        )
        if let request = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
            try await request.downloadAndInstall()
        }
        guard let analyzerFormat = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [transcriber]) else {
            throw SpeechCaptureError.localeUnsupported
        }

        let analyzer = SpeechAnalyzer(modules: [transcriber])
        let (inputSequence, continuation) = AsyncStream.makeStream(of: AnalyzerInput.self)

        let resultsTask = Task {
            var finalized = ""
            do {
                for try await result in transcriber.results {
                    let text = String(result.text.characters)
                    if result.isFinal {
                        finalized += text
                        onText(finalized)
                    } else {
                        onText(finalized + text)
                    }
                }
            } catch {
                // The stream ends with an error on cancel; whatever was delivered is kept.
            }
        }

        lock.withLock {
            self.analyzer = analyzer
            self.inputContinuation = continuation
            self.resultsTask = resultsTask
        }

        try await analyzer.start(inputSequence: inputSequence)

        let feeder = AnalyzerFeeder(continuation: continuation, outputFormat: analyzerFormat)
        do {
            _ = try microphone.start { buffer in feeder.feed(buffer) }
        } catch {
            await cancel()
            throw error
        }
    }

    func finish() async {
        microphone.stop()
        let (analyzer, continuation, task) = lock.withLock { (self.analyzer, self.inputContinuation, self.resultsTask) }
        continuation?.finish()
        if let analyzer {
            do {
                try await analyzer.finalizeAndFinishThroughEndOfInput()
            } catch {
                await analyzer.cancelAndFinishNow()
            }
        }
        await task?.value
        clear()
    }

    func cancel() async {
        microphone.stop()
        let (analyzer, continuation, task) = lock.withLock { (self.analyzer, self.inputContinuation, self.resultsTask) }
        continuation?.finish()
        task?.cancel()
        await analyzer?.cancelAndFinishNow()
        clear()
    }

    private func clear() {
        lock.withLock {
            analyzer = nil
            inputContinuation = nil
            resultsTask = nil
        }
    }
}

/// Converts microphone buffers to the analyzer's format and forwards them. Called on the audio thread.
private final class AnalyzerFeeder: @unchecked Sendable {
    private let continuation: AsyncStream<AnalyzerInput>.Continuation
    private let outputFormat: AVAudioFormat
    private var converter: AVAudioConverter?

    init(continuation: AsyncStream<AnalyzerInput>.Continuation, outputFormat: AVAudioFormat) {
        self.continuation = continuation
        self.outputFormat = outputFormat
    }

    func feed(_ buffer: AVAudioPCMBuffer) {
        if buffer.format == outputFormat {
            continuation.yield(AnalyzerInput(buffer: buffer))
            return
        }
        if converter == nil || converter?.inputFormat != buffer.format {
            converter = AVAudioConverter(from: buffer.format, to: outputFormat)
        }
        guard let converter else { return }

        let ratio = outputFormat.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount((Double(buffer.frameLength) * ratio).rounded(.up)) + 1
        guard let output = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: capacity) else { return }

        let state = ConversionState()
        nonisolated(unsafe) let source = buffer
        var error: NSError?
        let status = converter.convert(to: output, error: &error) { _, inputStatus in
            if state.consumed {
                inputStatus.pointee = .noDataNow
                return nil
            }
            state.consumed = true
            inputStatus.pointee = .haveData
            return source
        }
        if status != .error, error == nil, output.frameLength > 0 {
            continuation.yield(AnalyzerInput(buffer: output))
        }
    }
}

private final class ConversionState: @unchecked Sendable {
    var consumed = false
}
