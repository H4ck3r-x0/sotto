import AppKit

/// The little moments: a trackpad tap when recording starts, a soft chime
/// and tap when your words land. Both toggleable in Settings.
@MainActor
final class FeedbackService {
    private var soundsEnabled: Bool {
        UserDefaults.standard.object(forKey: "feedback.sounds") as? Bool ?? true
    }
    private var hapticsEnabled: Bool {
        UserDefaults.standard.object(forKey: "feedback.haptics") as? Bool ?? true
    }

    func recordingStarted() {
        haptic(.generic)
        play("Pop", volume: 0.20)
    }

    func inserted() {
        haptic(.levelChange)
        play("Tink", volume: 0.16)
    }

    func failed() {
        play("Basso", volume: 0.25)
    }

    private func play(_ name: String, volume: Float) {
        guard soundsEnabled, let sound = NSSound(named: name) else { return }
        sound.volume = volume
        sound.play()
    }

    private func haptic(_ pattern: NSHapticFeedbackManager.FeedbackPattern) {
        guard hapticsEnabled else { return }
        NSHapticFeedbackManager.defaultPerformer.perform(pattern, performanceTime: .default)
    }
}
