import AppKit
import Carbon.HIToolbox

enum TextInserterError: LocalizedError {
    case accessibilityDenied

    var errorDescription: String? {
        switch self {
        case .accessibilityDenied:
            "Sotto needs the Accessibility permission to type into other apps."
        }
    }
}

/// Inserts text at the cursor in whatever app has focus.
///
/// Default method is synthetic typing (Unicode keyboard events): it works in
/// every input that accepts a keyboard — web rich-text editors like X's
/// composer, terminals, even fields that block paste — and never touches the
/// clipboard. Paste (⌘V with clipboard save/restore) remains available in
/// Settings for apps that prefer it.
@MainActor
final class TextInserter {
    private var method: String {
        UserDefaults.standard.string(forKey: "insertion.method") ?? "type"
    }

    func insert(_ text: String) async throws {
        guard AXIsProcessTrusted() else {
            throw TextInserterError.accessibilityDenied
        }
        if method == "paste" {
            await insertViaPasteboard(text)
        } else {
            await insertByTyping(text)
        }
    }

    // MARK: - Typing (default)

    private func insertByTyping(_ text: String) async {
        let source = CGEventSource(stateID: .combinedSessionState)

        // Chunk on character boundaries so emoji/combined marks never split.
        var chunk: [UniChar] = []
        var chunks: [[UniChar]] = []
        for character in text {
            let units = Array(String(character).utf16)
            if chunk.count + units.count > 20 {
                chunks.append(chunk)
                chunk = []
            }
            chunk.append(contentsOf: units)
        }
        if !chunk.isEmpty { chunks.append(chunk) }

        for var units in chunks {
            let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: true)
            let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: false)
            keyDown?.flags = []
            keyUp?.flags = []
            keyDown?.keyboardSetUnicodeString(stringLength: units.count, unicodeString: &units)
            keyUp?.keyboardSetUnicodeString(stringLength: units.count, unicodeString: &units)
            keyDown?.post(tap: .cghidEventTap)
            keyUp?.post(tap: .cghidEventTap)
            // A breath between chunks so slower editors keep up.
            try? await Task.sleep(for: .milliseconds(6))
        }
    }

    // MARK: - Paste (optional)

    private func insertViaPasteboard(_ text: String) async {
        let pasteboard = NSPasteboard.general
        let saved = savedItems(from: pasteboard)

        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)

        let source = CGEventSource(stateID: .combinedSessionState)
        let keyDown = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_V), keyDown: true)
        let keyUp = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_V), keyDown: false)
        keyDown?.flags = .maskCommand
        keyUp?.flags = .maskCommand
        keyDown?.post(tap: .cghidEventTap)
        keyUp?.post(tap: .cghidEventTap)

        // Long grace period: some web editors consume the clipboard late.
        try? await Task.sleep(for: .milliseconds(900))
        pasteboard.clearContents()
        pasteboard.writeObjects(saved)
    }

    private func savedItems(from pasteboard: NSPasteboard) -> [NSPasteboardItem] {
        (pasteboard.pasteboardItems ?? []).map { item in
            let copy = NSPasteboardItem()
            for type in item.types {
                if let data = item.data(forType: type) {
                    copy.setData(data, forType: type)
                }
            }
            return copy
        }
    }
}
