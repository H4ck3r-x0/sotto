@preconcurrency import AVFoundation
import Accelerate

enum AudioCaptureError: LocalizedError {
    case converterUnavailable

    var errorDescription: String? {
        switch self {
        case .converterUnavailable:
            "Could not convert microphone audio into the engine's format."
        }
    }
}

/// Captures microphone audio with AVAudioEngine, converts it to the
/// transcription engine's preferred format, and reports input levels.
///
/// The engine is built and `prepare()`d ahead of time (`prewarm`) so that a
/// push-to-talk press only has to flip it on — `AVAudioEngine.start()` on a
/// cold engine costs ~250 ms, which is enough to clip a first syllable.
@MainActor
final class AudioCaptureService {
    /// Bridges the audio-thread tap to the per-recording stream. Written on
    /// the main thread only while the engine is stopped (no tap callbacks).
    private nonisolated final class TapRelay: @unchecked Sendable {
        var continuation: AsyncStream<AVAudioPCMBuffer>.Continuation?
        var onLevel: (@Sendable (Float) -> Void)?
    }

    private var engine: AVAudioEngine?
    private let relay = TapRelay()
    private var preparedNativeFormat: AVAudioFormat?
    private var preparedTargetFormat: AVAudioFormat?

    /// Builds and prepares the capture engine for `targetFormat`. Safe to
    /// call repeatedly; rebuilds only when the mic's native format changed
    /// (e.g. after switching to a headset).
    func prewarm(targetFormat: AVAudioFormat) {
        if let engine,
           preparedTargetFormat == targetFormat,
           engine.inputNode.outputFormat(forBus: 0) == preparedNativeFormat {
            return
        }
        teardown()

        let engine = AVAudioEngine()
        let input = engine.inputNode
        let nativeFormat = input.outputFormat(forBus: 0)
        guard nativeFormat.sampleRate > 0,
              let converter = AVAudioConverter(from: nativeFormat, to: targetFormat) else {
            return
        }

        let relay = self.relay
        input.installTap(onBus: 0, bufferSize: 2048, format: nativeFormat) { @Sendable buffer, _ in
            relay.onLevel?(Self.normalizedLevel(of: buffer))
            if let continuation = relay.continuation,
               let converted = Self.convert(buffer, using: converter, to: targetFormat) {
                continuation.yield(converted)
            }
        }

        engine.prepare()
        self.engine = engine
        preparedNativeFormat = nativeFormat
        preparedTargetFormat = targetFormat
        slog("audio prewarmed")
    }

    /// Starts capture. The returned stream yields converted buffers and
    /// finishes when `stop()` is called.
    func start(
        targetFormat: AVAudioFormat,
        onLevel: @escaping @Sendable (Float) -> Void
    ) throws -> AsyncStream<AVAudioPCMBuffer> {
        prewarm(targetFormat: targetFormat)
        guard let engine else { throw AudioCaptureError.converterUnavailable }

        let (stream, continuation) = AsyncStream.makeStream(of: AVAudioPCMBuffer.self)
        relay.continuation = continuation
        relay.onLevel = onLevel
        try engine.start()
        return stream
    }

    func stop() {
        guard let engine, engine.isRunning else { return }
        engine.stop()
        slog("audio stopped")
        relay.continuation?.finish()
        relay.continuation = nil
        relay.onLevel = nil
        // Stopped engines restart fast; keep it prepared for the next press.
        engine.prepare()
    }

    private func teardown() {
        engine?.inputNode.removeTap(onBus: 0)
        engine?.stop()
        engine = nil
        relay.continuation?.finish()
        relay.continuation = nil
        relay.onLevel = nil
    }

    private nonisolated static func convert(
        _ buffer: AVAudioPCMBuffer,
        using converter: AVAudioConverter,
        to format: AVAudioFormat
    ) -> sending AVAudioPCMBuffer? {
        let ratio = format.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 16
        guard let output = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: capacity) else {
            return nil
        }

        nonisolated(unsafe) var consumed = false
        var conversionError: NSError?
        let status = converter.convert(to: output, error: &conversionError) { _, inputStatus in
            if consumed {
                inputStatus.pointee = .noDataNow
                return nil
            }
            consumed = true
            inputStatus.pointee = .haveData
            return buffer
        }
        return status == .error ? nil : output
    }

    /// Root-mean-square level mapped to 0...1 for the HUD meter.
    private nonisolated static func normalizedLevel(of buffer: AVAudioPCMBuffer) -> Float {
        guard let data = buffer.floatChannelData?[0], buffer.frameLength > 0 else { return 0 }
        var rms: Float = 0
        vDSP_rmsqv(data, 1, &rms, vDSP_Length(buffer.frameLength))
        // Perceptual-ish curve: quiet speech still moves the meter.
        return min(1, pow(rms * 12, 0.7))
    }
}
