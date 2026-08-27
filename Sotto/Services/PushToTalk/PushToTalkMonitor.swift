import AppKit

/// Watches for the push-to-talk shortcut globally. Requires the Accessibility
/// permission to observe events in other apps.
///
/// Modifier-only hotkeys use NSEvent monitors (holding a modifier never types
/// anything, so nothing needs intercepting). Key-based hotkeys use a CGEvent
/// tap so the held key is swallowed instead of typed into the focused app.
@MainActor
final class PushToTalkMonitor {
    var onPress: (() -> Void)?
    var onRelease: (() -> Void)?

    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var eventTap: CFMachPort?
    private var tapSource: CFRunLoopSource?

    private var hotkey = Hotkey.current
    private var isHolding = false

    /// Ignore taps shorter than this — they're almost always accidental.
    private let minimumHold: TimeInterval = 0.15
    private var pressedAt: Date?

    init() {
        NotificationCenter.default.addObserver(
            forName: Hotkey.changedNotification, object: nil, queue: .main
        ) { @Sendable [weak self] _ in
            MainActor.assumeIsolated { self?.start() }
        }
    }

    func start() {
        stop()
        hotkey = Hotkey.current
        slog("PTT monitoring \(hotkey.displayName)")
        if hotkey.isModifierOnly {
            startModifierMonitors()
        } else {
            startEventTap()
        }
    }

    func stop() {
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
        globalMonitor = nil
        localMonitor = nil
        if let eventTap {
            CGEvent.tapEnable(tap: eventTap, enable: false)
            CFMachPortInvalidate(eventTap)
        }
        if let tapSource { CFRunLoopRemoveSource(CFRunLoopGetMain(), tapSource, .commonModes) }
        eventTap = nil
        tapSource = nil
        isHolding = false
    }

    // MARK: - Shared press/release

    private func keyWentDown() {
        guard !isHolding else { return }
        isHolding = true
        pressedAt = Date()
        onPress?()
    }

    private func keyWentUp() {
        guard isHolding else { return }
        isHolding = false
        let heldLongEnough = pressedAt.map { Date().timeIntervalSince($0) >= minimumHold } ?? false
        pressedAt = nil
        if heldLongEnough { onRelease?() }
    }

    // MARK: - Modifier-only path

    private func startModifierMonitors() {
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            Task { @MainActor in self?.handleFlagsChanged(event) }
        }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            self?.handleFlagsChanged(event)
            return event
        }
    }

    private func handleFlagsChanged(_ event: NSEvent) {
        // Track the specific key, not just the modifier flag — e.g. `.function`
        // is also set by arrow/nav keys, and `.option` by the other Option key.
        guard event.keyCode == hotkey.keyCode else { return }
        if event.modifierFlags.contains(hotkey.modifierFlags) {
            keyWentDown()
        } else {
            keyWentUp()
        }
    }

    // MARK: - Key-based path (event tap)

    private func startEventTap() {
        let mask = (1 << CGEventType.keyDown.rawValue) | (1 << CGEventType.keyUp.rawValue)
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(mask),
            callback: Self.tapCallback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            serror("event tap creation failed — is Accessibility granted?")
            return
        }
        eventTap = tap
        tapSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), tapSource, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        slog("event tap enabled=\(CGEvent.tapIsEnabled(tap: tap))")
    }

    private nonisolated static let tapCallback: CGEventTapCallBack = { _, type, event, refcon in
        guard let refcon else { return Unmanaged.passUnretained(event) }
        let monitor = Unmanaged<PushToTalkMonitor>.fromOpaque(refcon).takeUnretainedValue()
        return monitor.handleTap(type: type, event: event)
    }

    /// Runs on the main run loop (where the tap source is scheduled).
    private nonisolated func handleTap(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        // Safe: the tap source is scheduled on the main run loop, so this is
        // main-thread despite the nonisolated C callback signature. Only the
        // swallow decision crosses into the actor — CGEvent isn't Sendable.
        nonisolated(unsafe) let event = event
        let swallow = MainActor.assumeIsolated { () -> Bool in
            switch type {
            case .tapDisabledByTimeout, .tapDisabledByUserInput:
                if let eventTap { CGEvent.tapEnable(tap: eventTap, enable: true) }
                return false
            case .keyDown, .keyUp:
                break
            default:
                return false
            }

            let keyCode = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
            guard keyCode == hotkey.keyCode else { return false }

            if type == .keyDown {
                // Without the required modifiers, let the key type normally.
                guard event.flags.contains(requiredTapFlags) else { return false }
                keyWentDown()
                return true // swallow, including auto-repeats
            }

            guard isHolding else { return false }
            keyWentUp()
            return true
        }
        return swallow ? nil : Unmanaged.passUnretained(event)
    }

    private var requiredTapFlags: CGEventFlags {
        var flags = CGEventFlags()
        let mods = hotkey.modifierFlags
        if mods.contains(.command) { flags.insert(.maskCommand) }
        if mods.contains(.option) { flags.insert(.maskAlternate) }
        if mods.contains(.control) { flags.insert(.maskControl) }
        if mods.contains(.shift) { flags.insert(.maskShift) }
        return flags
    }
}
