import AppKit

/// A user-recorded push-to-talk shortcut. Two shapes:
/// - a single modifier key held on its own (Right ⌥, 🌐 Fn, …), observed
///   via `.flagsChanged`
/// - a regular key, bare (F-keys only) or with modifiers (⌥Space, ⌘⇧D, …),
///   intercepted by an event tap so holding it never types into the app
struct Hotkey: Codable, Equatable {
    var keyCode: UInt16
    /// Raw `NSEvent.ModifierFlags` required alongside the key.
    var modifiers: UInt
    var isModifierOnly: Bool
    var displayName: String

    static let defaultsKey = "hotkey"
    static let changedNotification = Notification.Name("sottoHotkeyChanged")

    static let rightOption = modifierOnly(keyCode: 61)!

    static var current: Hotkey {
        if let data = UserDefaults.standard.data(forKey: defaultsKey),
           let hotkey = try? JSONDecoder().decode(Hotkey.self, from: data) {
            return hotkey
        }
        // Migrate the old preset-based setting.
        switch UserDefaults.standard.string(forKey: "pushToTalkKey") {
        case "rightCommand": return modifierOnly(keyCode: 54) ?? .rightOption
        case "rightControl": return modifierOnly(keyCode: 62) ?? .rightOption
        case "globe": return modifierOnly(keyCode: 63) ?? .rightOption
        default: return .rightOption
        }
    }

    func save() {
        slog("hotkey saved: \(displayName)")
        if let data = try? JSONEncoder().encode(self) {
            UserDefaults.standard.set(data, forKey: Self.defaultsKey)
        }
        NotificationCenter.default.post(name: Self.changedNotification, object: nil)
    }

    var modifierFlags: NSEvent.ModifierFlags { .init(rawValue: modifiers) }

    /// Shown when a key can clash with a system-level binding.
    var caveat: String? {
        if isModifierOnly && keyCode == 63 {
            return "If 🌐 Fn switches your input language, set “Press 🌐 key to: Do Nothing” in System Settings → Keyboard."
        }
        return nil
    }

    // MARK: - Building from recorded events

    /// The modifier keys that can act as a hotkey on their own.
    static func modifierOnly(keyCode: UInt16) -> Hotkey? {
        let table: [UInt16: (NSEvent.ModifierFlags, String)] = [
            55: (.command, "Left ⌘"), 54: (.command, "Right ⌘"),
            58: (.option, "Left ⌥"), 61: (.option, "Right ⌥"),
            59: (.control, "Left ⌃"), 62: (.control, "Right ⌃"),
            56: (.shift, "Left ⇧"), 60: (.shift, "Right ⇧"),
            63: (.function, "🌐 Fn"),
        ]
        guard let (flag, name) = table[keyCode] else { return nil }
        return Hotkey(keyCode: keyCode, modifiers: flag.rawValue, isModifierOnly: true, displayName: name)
    }

    /// Builds a key-based hotkey from a recorded key press. Returns nil for a
    /// bare character key — holding one has to be swallowed, which would make
    /// that character impossible to type. F-keys are safe to use bare.
    static func from(event: NSEvent) -> Hotkey? {
        let mods = event.modifierFlags.intersection([.command, .option, .control, .shift])
        guard !mods.isEmpty || bareSafeKeys.contains(event.keyCode) else { return nil }

        var name = ""
        if mods.contains(.control) { name += "⌃" }
        if mods.contains(.option) { name += "⌥" }
        if mods.contains(.shift) { name += "⇧" }
        if mods.contains(.command) { name += "⌘" }
        name += keyName(for: event)

        return Hotkey(keyCode: event.keyCode, modifiers: mods.rawValue, isModifierOnly: false, displayName: name)
    }

    /// F1–F20: keys that do nothing when held, so they may be used unmodified.
    private static let bareSafeKeys: Set<UInt16> = [
        122, 120, 99, 118, 96, 97, 98, 100, 101, 109,
        103, 111, 105, 107, 113, 106, 64, 79, 80, 90,
    ]

    private static let specialKeyNames: [UInt16: String] = [
        49: "Space", 36: "Return", 48: "Tab", 51: "⌫", 117: "⌦",
        115: "Home", 119: "End", 116: "Page Up", 121: "Page Down",
        123: "←", 124: "→", 125: "↓", 126: "↑",
        122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5",
        97: "F6", 98: "F7", 100: "F8", 101: "F9", 109: "F10",
        103: "F11", 111: "F12", 105: "F13", 107: "F14", 113: "F15",
        106: "F16", 64: "F17", 79: "F18", 80: "F19", 90: "F20",
    ]

    private static func keyName(for event: NSEvent) -> String {
        if let name = specialKeyNames[event.keyCode] { return name }
        if let chars = event.charactersIgnoringModifiers, !chars.isEmpty {
            return chars.uppercased()
        }
        return "Key \(event.keyCode)"
    }
}
