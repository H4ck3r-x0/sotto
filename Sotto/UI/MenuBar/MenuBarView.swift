import SwiftUI

struct MenuBarView: View {
    @Environment(DictationController.self) private var dictation
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        Group {
            Text(statusLine)

            if !dictation.permissions.allGranted {
                Divider()
                if !dictation.permissions.microphoneGranted {
                    Button("Grant Microphone Access…") {
                        dictation.permissions.requestMicrophone()
                    }
                }
                if !dictation.permissions.accessibilityGranted {
                    Button("Grant Accessibility Access…") {
                        dictation.permissions.requestAccessibility()
                    }
                }
            }

            Divider()

            Button("Settings…") { openSettings() }
                .keyboardShortcut(",")

            Divider()

            Button("Quit Sotto") { NSApp.terminate(nil) }
                .keyboardShortcut("q")
        }
        .onAppear { dictation.permissions.refresh() }
    }

    private var statusLine: String {
        switch dictation.state {
        case .idle:
            dictation.modelReady ? "Hold \(Hotkey.current.displayName) to dictate" : "Getting ready…"
        case .preparingModel: "Downloading speech model…"
        case .recording: "Listening…"
        case .transcribing: "Transcribing…"
        case .failed(let message): message
        }
    }
}
