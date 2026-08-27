import AppKit
import Observation

/// Composition root. Owns every long-lived service and wires them together.
@MainActor
final class AppEnvironment {
    let dictation: DictationController
    private let pushToTalk: PushToTalkMonitor
    private let hud: HUDPanelController

    init() {
        let dictation = DictationController()
        self.dictation = dictation
        self.hud = HUDPanelController(dictation: dictation)
        self.pushToTalk = PushToTalkMonitor()

        pushToTalk.onPress = { [weak dictation] in slog("PTT press"); dictation?.beginDictation() }
        pushToTalk.onRelease = { [weak dictation] in slog("PTT release"); dictation?.endDictation() }
        pushToTalk.start()

        observeStateForHUD()

        Task { await dictation.prepare() }
    }

    /// Shows the HUD whenever dictation leaves `.idle`, hides it when it returns.
    private func observeStateForHUD() {
        withObservationTracking {
            _ = dictation.state
        } onChange: { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                slog("state -> \(self.dictation.state), hud visible=\(self.dictation.state.isActive)")
                self.hud.setVisible(self.dictation.state.isActive)
                self.observeStateForHUD()
            }
        }
    }
}
