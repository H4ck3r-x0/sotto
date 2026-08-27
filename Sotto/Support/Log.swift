import Foundation
import os

let sottoLogger = Logger(subsystem: "app.sotto", category: "pipeline")

private let debugEnabled = UserDefaults.standard.bool(forKey: "debugLogging")
private let logEpoch = Date()

/// Debug tracing — no-op unless `debugLogging` is set in defaults.
func slog(_ message: String) {
    guard debugEnabled else { return }
    sottoLogger.debug("\(message, privacy: .public)")
    let t = String(format: "%8.3f", Date().timeIntervalSince(logEpoch))
    FileHandle.standardError.write(Data("[sotto \(t)] \(message)\n".utf8))
}

/// Errors — always recorded.
func serror(_ message: String) {
    sottoLogger.error("\(message, privacy: .public)")
    FileHandle.standardError.write(Data("[sotto ERROR] \(message)\n".utf8))
}
