import SwiftUI

/// The push-to-talk shortcut recorder: click the button, then press the
/// shortcut you want — a key combo, an F-key, or a single modifier key
/// pressed and released on its own.
struct HotkeyRecorderSection: View {
    @State private var hotkey = Hotkey.current
    @State private var isRecording = false
    @State private var rejectedBareKey = false
    @State private var monitor: Any?

    var body: some View {
        Section {
            LabeledContent("Hold to dictate") {
                Button {
                    isRecording ? stopRecording() : beginRecording()
                } label: {
                    Text(isRecording ? "Press your shortcut…" : hotkey.displayName)
                        .frame(minWidth: 140)
                }
            }
        } footer: {
            if isRecording {
                Text("Press a key combo, press and release a single modifier key (like Right ⌥), or press Esc to cancel.")
            } else if rejectedBareKey {
                Text("A bare letter key would be unusable for typing while set as the shortcut — use an F-key, a modifier key, or add ⌘⌥⌃⇧.")
                    .foregroundStyle(.orange)
            } else if let caveat = hotkey.caveat {
                Text(caveat)
            }
        }
        .onDisappear { stopRecording() }
    }

    private func beginRecording() {
        isRecording = true
        rejectedBareKey = false

        // A modifier pressed alone becomes the hotkey once it's released
        // (releasing is what distinguishes "Right ⌥ alone" from "⌥ + key").
        var candidateModifier: Hotkey?

        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { event in
            if event.type == .keyDown {
                if event.keyCode == 53 { // Esc cancels
                    stopRecording()
                } else if let recorded = Hotkey.from(event: event) {
                    commit(recorded)
                } else {
                    rejectedBareKey = true
                    NSSound.beep()
                }
                return nil
            }

            let held = event.modifierFlags.intersection([.command, .option, .control, .shift, .function])
            if !held.isEmpty, let candidate = Hotkey.modifierOnly(keyCode: event.keyCode) {
                candidateModifier = candidate
            } else if held.isEmpty, let candidate = candidateModifier {
                commit(candidate)
            }
            return nil
        }
    }

    private func commit(_ recorded: Hotkey) {
        hotkey = recorded
        recorded.save()
        stopRecording()
    }

    private func stopRecording() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        isRecording = false
    }
}
