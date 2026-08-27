import ServiceManagement
import SwiftUI

struct SettingsView: View {
    var body: some View {
        TabView {
            Tab("General", systemImage: "gearshape") {
                GeneralSettingsTab()
            }
            Tab("Dictation", systemImage: "waveform") {
                DictationSettingsTab()
            }
            Tab("About", systemImage: "info.circle") {
                AboutSettingsTab()
            }
        }
        .frame(width: 420)
    }
}

// MARK: - General

private struct GeneralSettingsTab: View {
    @Environment(DictationController.self) private var dictation
    @AppStorage("feedback.sounds") private var soundEffects = true
    @AppStorage("feedback.haptics") private var hapticFeedback = true

    var body: some View {
        Form {
            HotkeyRecorderSection()

            Section {
                Toggle("Launch at login", isOn: launchAtLogin)
                Toggle("Sound effects", isOn: $soundEffects)
                Toggle("Haptic feedback", isOn: $hapticFeedback)
            }

            Section("Permissions") {
                permissionRow(
                    "Microphone",
                    granted: dictation.permissions.microphoneGranted,
                    action: { dictation.permissions.requestMicrophone() }
                )
                permissionRow(
                    "Accessibility",
                    granted: dictation.permissions.accessibilityGranted,
                    action: { dictation.permissions.requestAccessibility() }
                )
            }
        }
        .formStyle(.grouped)
        .fixedSize(horizontal: false, vertical: true)
        .onAppear { dictation.permissions.refresh() }
    }

    private var launchAtLogin: Binding<Bool> {
        Binding(
            get: { SMAppService.mainApp.status == .enabled },
            set: { enable in
                do {
                    if enable {
                        try SMAppService.mainApp.register()
                    } else {
                        try SMAppService.mainApp.unregister()
                    }
                } catch {
                    serror("launch at login failed: \(error)")
                }
            }
        )
    }

    @ViewBuilder
    private func permissionRow(_ name: String, granted: Bool, action: @escaping () -> Void) -> some View {
        LabeledContent(name) {
            if granted {
                Label("Granted", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .labelStyle(.titleAndIcon)
            } else {
                Button("Grant…", action: action)
            }
        }
    }
}

// MARK: - Dictation

private struct DictationSettingsTab: View {
    @AppStorage("format.removeFillers") private var removeFillers = true
    @AppStorage("format.capitalize") private var capitalizeSentences = true
    @AppStorage("format.terminalPunctuation") private var terminalPunctuation = false
    @AppStorage("insertion.method") private var insertionMethod = "type"

    var body: some View {
        Form {
            Section {
                Picker("Insert text by", selection: $insertionMethod) {
                    Text("Typing it out").tag("type")
                    Text("Pasting (⌘V)").tag("paste")
                }
            } footer: {
                Text("Typing works in every app and leaves your clipboard alone.")
            }

            Section("Formatting") {
                Toggle("Remove filler words (“um”, “uh”)", isOn: $removeFillers)
                Toggle("Capitalize sentences", isOn: $capitalizeSentences)
                Toggle("End with punctuation", isOn: $terminalPunctuation)
            }

            Section {
                LabeledContent("Custom words") {
                    Button("Edit Dictionary…") {
                        DictionaryCorrector.createFileIfMissing()
                        NSWorkspace.shared.open(DictionaryCorrector.fileURL)
                    }
                }
            } footer: {
                Text("Teach Sotto your names and jargon — “cloud code” → “Claude Code”.")
            }
        }
        .formStyle(.grouped)
        .fixedSize(horizontal: false, vertical: true)
    }
}

// MARK: - About

private struct AboutSettingsTab: View {
    @Environment(DictationController.self) private var dictation

    private var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 6) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 72, height: 72)
                Text("Sotto")
                    .font(.title2.weight(.semibold))
                Text("Version \(version)")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .padding(.top, 24)

            Form {
                Section {
                    LabeledContent("Engine", value: "Apple on-device")
                    LabeledContent("Language", value: dictation.languageName)
                } footer: {
                    Text("Transcription runs entirely on this Mac. Audio never leaves it.")
                }
            }
            .formStyle(.grouped)
            .fixedSize(horizontal: false, vertical: true)
        }
    }
}
