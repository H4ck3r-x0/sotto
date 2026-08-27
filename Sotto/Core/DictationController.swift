import AVFoundation
import Observation

/// The dictation state machine: idle → recording → transcribing → idle.
/// One instance drives the menu bar item, the HUD, and settings.
@MainActor
@Observable
final class DictationController {
    enum State: Equatable {
        case idle
        case preparingModel
        case recording
        case transcribing
        case failed(String)

        var isActive: Bool {
            switch self {
            case .recording, .transcribing: true
            default: false
            }
        }
    }

    private(set) var state: State = .idle
    /// Words the engine has committed to.
    private(set) var finalizedTranscript = ""
    /// The in-flight hypothesis — shown dimmer/tinted in the HUD.
    private(set) var volatileTranscript = ""

    var liveTranscript: String { finalizedTranscript + volatileTranscript }
    /// 0...1 microphone level for the HUD meter.
    private(set) var audioLevel: Float = 0
    private(set) var modelReady = false

    var permissions = PermissionsService()

    /// Shown in Settings › About.
    var languageName: String { engine.localeDisplayName }

    private let engine: any TranscriptionEngine = AppleSpeechEngine()
    private let audio = AudioCaptureService()
    private let inserter = TextInserter()
    private let feedback = FeedbackService()
    private var sessionTask: Task<Void, Never>?

    /// Downloads / verifies the on-device speech model. Safe to call repeatedly.
    func prepare() async {
        state = .preparingModel
        do {
            try await engine.prepare(locale: .current)
            modelReady = true
            state = .idle
            if let format = await engine.prewarm() {
                audio.prewarm(targetFormat: format)
            }
        } catch {
            state = .failed("Speech model unavailable: \(error.localizedDescription)")
        }
    }

    func beginDictation() {
        guard state == .idle, modelReady else {
            slog("beginDictation refused: state=\(state) modelReady=\(modelReady)")
            return
        }
        guard permissions.microphoneGranted else {
            permissions.requestMicrophone()
            return
        }

        state = .recording
        finalizedTranscript = ""
        volatileTranscript = ""
        feedback.recordingStarted()

        sessionTask = Task { [weak self] in
            guard let self else { return }
            do {
                let session = try await engine.beginSession()
                slog("session began, format=\(session.inputFormat)")
                let buffers = try audio.start(targetFormat: session.inputFormat) { [weak self] level in
                    Task { @MainActor in self?.audioLevel = level }
                }

                // Feed audio and read results concurrently until the session ends.
                // Task {} inherits the main actor here, so the non-Sendable
                // session never leaves it.
                let feeding = Task { try await session.feed(buffers) }
                for try await update in session.results {
                    self.finalizedTranscript = update.finalized
                    self.volatileTranscript = update.volatile
                }
                slog("results stream ended")
                try await feeding.value
                slog("feed task finished")

                var text = self.liveTranscript.trimmingCharacters(in: .whitespacesAndNewlines)
                text = RuleBasedFormatter().format(text)
                text = DictionaryCorrector().correct(text)
                slog("final text: \(text.count) chars")
                if !text.isEmpty {
                    self.state = .transcribing
                    try await self.inserter.insert(text)
                    slog("inserted")
                    self.feedback.inserted()
                }
                self.state = .idle
            } catch is CancellationError {
                slog("session cancelled")
                self.state = .idle
            } catch {
                serror("session error: \(error)")
                self.feedback.failed()
                self.state = .failed(error.localizedDescription)
                try? await Task.sleep(for: .seconds(2))
                if case .failed = self.state { self.state = .idle }
            }
            self.audioLevel = 0
            if let format = await self.engine.prewarm() {
                self.audio.prewarm(targetFormat: format)
            }
        }
    }

    func endDictation() {
        guard state == .recording else { return }
        // Stopping capture ends the buffer stream; the session then finalizes
        // on its own and delivers the final results. Cancelling here would
        // throw the transcript away.
        audio.stop()
    }

}
