import SwiftUI

@main
struct SottoApp: App {
    @State private var environment = AppEnvironment()

    var body: some Scene {
        MenuBarExtra {
            MenuBarView()
                .environment(environment.dictation)
        } label: {
            Image(systemName: environment.dictation.state.isActive
                ? "waveform.circle.fill"
                : "waveform.circle")
        }
        .menuBarExtraStyle(.menu)

        Settings {
            SettingsView()
                .environment(environment.dictation)
        }
    }
}
