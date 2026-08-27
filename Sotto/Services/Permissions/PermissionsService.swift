import AVFoundation
import AppKit
import Observation

/// Tracks the two permissions Sotto needs: microphone (to hear you) and
/// Accessibility (to watch the push-to-talk key and paste into other apps).
@MainActor
@Observable
final class PermissionsService {
    private(set) var microphoneGranted: Bool
    private(set) var accessibilityGranted: Bool

    init() {
        microphoneGranted = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
        accessibilityGranted = AXIsProcessTrusted()
    }

    var allGranted: Bool { microphoneGranted && accessibilityGranted }

    func refresh() {
        microphoneGranted = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
        accessibilityGranted = AXIsProcessTrusted()
    }

    func requestMicrophone() {
        AVCaptureDevice.requestAccess(for: .audio) { granted in
            Task { @MainActor in self.microphoneGranted = granted }
        }
    }

    /// Shows the system prompt and deep-links to the Accessibility pane.
    func requestAccessibility() {
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        accessibilityGranted = AXIsProcessTrustedWithOptions(options)
    }
}
