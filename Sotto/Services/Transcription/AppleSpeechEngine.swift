import AVFoundation
import Speech

enum AppleSpeechEngineError: LocalizedError {
    case localeUnsupported(Locale)
    case noAudioFormat

    var errorDescription: String? {
        switch self {
        case .localeUnsupported(let locale):
            "On-device transcription does not support “\(locale.identifier)” yet."
        case .noAudioFormat:
            "The speech engine did not report a usable audio format."
        }
    }
}

/// Transcription backed by Apple's on-device SpeechAnalyzer (macOS 26+).
/// The OS owns and manages the model, so the app process stays lightweight.
@MainActor
final class AppleSpeechEngine: TranscriptionEngine {
    private var locale: Locale = .current
    private var prewarmedSession: AppleSpeechSession?

    var localeDisplayName: String {
        let id = locale.identifier(.bcp47)
        return Locale.current.localizedString(forIdentifier: id) ?? id
    }

    func prepare(locale: Locale) async throws {
        let supported = await SpeechTranscriber.supportedLocales
        guard let match = supported.first(where: {
            $0.identifier(.bcp47) == locale.identifier(.bcp47)
                || $0.language.languageCode == locale.language.languageCode
        }) else {
            throw AppleSpeechEngineError.localeUnsupported(locale)
        }
        self.locale = match

        // Triggers a one-time OS-managed model download when missing.
        let transcriber = SpeechTranscriber(
            locale: match,
            transcriptionOptions: [],
            reportingOptions: [.volatileResults],
            attributeOptions: []
        )
        if let request = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
            try await request.downloadAndInstall()
        }
    }

    @discardableResult
    func prewarm() async -> AVAudioFormat? {
        if prewarmedSession == nil {
            prewarmedSession = try? await makeSession()
            slog("session prewarmed")
        }
        return prewarmedSession?.inputFormat
    }

    func beginSession() async throws -> any TranscriptionSession {
        if let session = prewarmedSession {
            prewarmedSession = nil
            return session
        }
        return try await makeSession()
    }

    private func makeSession() async throws -> AppleSpeechSession {
        let transcriber = SpeechTranscriber(
            locale: locale,
            transcriptionOptions: [],
            reportingOptions: [.volatileResults],
            attributeOptions: []
        )
        let analyzer = SpeechAnalyzer(modules: [transcriber])

        guard let format = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [transcriber]) else {
            throw AppleSpeechEngineError.noAudioFormat
        }

        let (inputSequence, inputBuilder) = AsyncStream<AnalyzerInput>.makeStream()
        try await analyzer.start(inputSequence: inputSequence)

        return AppleSpeechSession(
            analyzer: analyzer,
            transcriber: transcriber,
            inputBuilder: inputBuilder,
            inputFormat: format
        )
    }


}

@MainActor
final class AppleSpeechSession: TranscriptionSession {
    nonisolated let inputFormat: AVAudioFormat
    nonisolated let results: AsyncThrowingStream<TranscriptUpdate, Error>

    private let analyzer: SpeechAnalyzer
    private let inputBuilder: AsyncStream<AnalyzerInput>.Continuation

    init(
        analyzer: SpeechAnalyzer,
        transcriber: SpeechTranscriber,
        inputBuilder: AsyncStream<AnalyzerInput>.Continuation,
        inputFormat: AVAudioFormat
    ) {
        self.analyzer = analyzer
        self.inputBuilder = inputBuilder
        self.inputFormat = inputFormat

        // Map SpeechTranscriber results into finalized + volatile aggregates.
        self.results = AsyncThrowingStream { continuation in
            let task = Task {
                var finalized = ""
                do {
                    for try await result in transcriber.results {
                        let text = String(result.text.characters)
                        if result.isFinal {
                            finalized += text
                            continuation.yield(TranscriptUpdate(finalized: finalized, volatile: ""))
                        } else {
                            continuation.yield(TranscriptUpdate(finalized: finalized, volatile: text))
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    func feed(_ buffers: AsyncStream<AVAudioPCMBuffer>) async throws {
        for await buffer in buffers {
            inputBuilder.yield(AnalyzerInput(buffer: buffer))
        }
        inputBuilder.finish()
        try await analyzer.finalizeAndFinishThroughEndOfInput()
    }
}
