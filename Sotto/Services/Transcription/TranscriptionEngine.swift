import AVFoundation

/// A single push-to-talk utterance being transcribed.
protocol TranscriptionSession {
    /// The audio format the engine wants to be fed.
    var inputFormat: AVAudioFormat { get }
    /// Rolling transcript updates. Finishes once the session is finalized.
    var results: AsyncThrowingStream<TranscriptUpdate, Error> { get }
    /// Consumes microphone buffers until the stream ends, then finalizes.
    func feed(_ buffers: AsyncStream<AVAudioPCMBuffer>) async throws
}

struct TranscriptUpdate: Sendable {
    /// Text the engine has committed to.
    let finalized: String
    /// The current in-flight hypothesis — may still change.
    let volatile: String
}

/// Seam between the dictation pipeline and the speech-to-text backend
/// (Apple's on-device SpeechAnalyzer).
@MainActor
protocol TranscriptionEngine {
    /// Human-readable name of the language actually being transcribed.
    var localeDisplayName: String { get }
    /// Ensures the model for `locale` is present, downloading it if needed.
    func prepare(locale: Locale) async throws
    /// Builds the next session ahead of time so `beginSession` is instant.
    /// Returns the session's input format so audio capture can prewarm too.
    @discardableResult
    func prewarm() async -> AVAudioFormat?
    func beginSession() async throws -> any TranscriptionSession
}
