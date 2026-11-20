@preconcurrency import AVFoundation
import Foundation
import Observation
import TimeTrackerCore

/// Drives one listening session: permissions, engine fallback, live transcript, auto-finish on silence,
/// and handing the final text to `EntryService`.
@MainActor
@Observable
final class VoiceCaptureController {
    enum Phase: Equatable {
        case idle
        case preparing
        case listening
        case saving
        case done(String)
        case failed(String)
    }

    private(set) var phase: Phase = .idle
    private(set) var transcript = ""
    private(set) var engineName = ""

    /// When listening ends by itself (silence, time limit).
    let policy: ListeningPolicy
    /// False when running from a Lock Screen intent: iOS can't show permission prompts there,
    /// so only already-granted permissions are used.
    let allowsPermissionPrompts: Bool
    let source: EntrySource
    private let nothingHeardMessage: String

    init(
        policy: ListeningPolicy = .standard,
        allowsPermissionPrompts: Bool = true,
        source: EntrySource = .voice,
        nothingHeardMessage: String = "I didn't catch that. Tap the mic and try again."
    ) {
        self.policy = policy
        self.allowsPermissionPrompts = allowsPermissionPrompts
        self.source = source
        self.nothingHeardMessage = nothingHeardMessage
    }

    private var engine: (any TranscriptionEngine)?
    private var listeningStartedAt = Date()
    private var lastTranscriptChange = Date()
    private var watchdog: Task<Void, Never>?
    private var resetTask: Task<Void, Never>?
    private var session = 0

    var isBusy: Bool {
        switch phase {
        case .preparing, .listening, .saving: true
        default: false
        }
    }

    func toggle() {
        switch phase {
        case .listening: finish()
        case .preparing: cancel()
        case .saving: break
        default: start()
        }
    }

    func start() {
        guard !isBusy else { return }
        resetTask?.cancel()
        session += 1
        let current = session
        transcript = ""
        phase = .preparing
        Task { await begin(session: current) }
    }

    func finish() {
        guard phase == .listening, let engine else { return }
        watchdog?.cancel()
        phase = .saving
        let current = session
        Task {
            await engine.finish()
            await complete(session: current)
        }
    }

    func cancel() {
        watchdog?.cancel()
        session += 1
        let engine = self.engine
        self.engine = nil
        phase = .idle
        transcript = ""
        Task { await engine?.cancel() }
    }

    // MARK: - Private

    private func begin(session current: Int) async {
        let micAllowed = allowsPermissionPrompts
            ? await AVAudioApplication.requestRecordPermission()
            : AVAudioApplication.shared.recordPermission == .granted
        guard micAllowed else {
            fail(SpeechCaptureError.microphoneDenied.localizedDescription)
            return
        }

        var lastError: Error?
        for candidate in TranscriptionEngines.candidates(allowsPermissionPrompts: allowsPermissionPrompts) {
            guard current == session else { return }
            do {
                try await candidate.start { [weak self] text in
                    Task { @MainActor in self?.receive(text, session: current) }
                }
                guard current == session else {
                    await candidate.cancel()
                    return
                }
                engine = candidate
                engineName = candidate.displayName
                listeningStartedAt = Date()
                lastTranscriptChange = Date()
                phase = .listening
                startWatchdog(session: current)
                return
            } catch {
                lastError = error
                await candidate.cancel()
            }
        }
        fail(lastError?.localizedDescription ?? "Speech recognition isn't available right now.")
    }

    private func receive(_ text: String, session current: Int) {
        guard current == session, phase == .listening || phase == .saving else { return }
        let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned != transcript {
            transcript = cleaned
            lastTranscriptChange = Date()
        }
    }

    private func startWatchdog(session current: Int) {
        watchdog?.cancel()
        watchdog = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(200))
                guard let self, current == self.session, self.phase == .listening else { return }
                if self.shouldAutoFinish(now: Date()) {
                    self.finish()
                    return
                }
            }
        }
    }

    private func shouldAutoFinish(now: Date) -> Bool {
        policy.shouldFinish(
            startedAt: listeningStartedAt, lastTranscriptChange: lastTranscriptChange,
            hasTranscript: !transcript.isEmpty, now: now
        )
    }

    private func complete(session current: Int) async {
        guard current == session else { return }
        engine = nil
        let text = transcript
        guard !text.isEmpty else {
            fail(nothingHeardMessage)
            return
        }
        let outcome = await EntryService.shared.capture(text: text, source: source)
        guard current == session else { return }
        phase = .done(outcome.message)
        scheduleReset(after: 4)
    }

    private func fail(_ message: String) {
        engine = nil
        phase = .failed(message)
        scheduleReset(after: 6)
    }

    private func scheduleReset(after seconds: Double) {
        resetTask?.cancel()
        let current = session
        resetTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled, let self, current == self.session else { return }
            if !self.isBusy {
                self.phase = .idle
                self.transcript = ""
            }
        }
    }
}
