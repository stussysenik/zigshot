import AppKit
import Carbon

/// Registers global hotkeys (Cmd+Shift+3/4/5) via CGEvent tap.
/// Requires Screen Recording permission for the event tap to work.
final class HotkeyManager {
    enum Action {
        case captureFullscreen  // Cmd+Shift+3
        case captureArea        // Cmd+Shift+4
        case captureWindow      // Cmd+Shift+5
    }

    var callback: ((Action) -> Void)?
    private var eventTap: CFMachPort?

    func register(callback: @escaping (Action) -> Void) {
        self.callback = callback
        installEventTap()
    }

    private func installEventTap() {
        let mask: CGEventMask = 1 << CGEventType.keyDown.rawValue

        let refcon = Unmanaged.passUnretained(self).toOpaque()
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: hotkeyCallback,
            userInfo: refcon
        ) else {
            print("[HotkeyManager] Failed to create event tap. "
                + "Screen Recording permission may be required.")
            return
        }

        self.eventTap = tap
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
    }

    deinit {
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
    }
}

// MARK: - Event tap callback (C function pointer)

private func hotkeyCallback(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    refcon: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    guard type == .keyDown, let refcon = refcon else {
        return Unmanaged.passRetained(event)
    }

    let manager = Unmanaged<HotkeyManager>.fromOpaque(refcon).takeUnretainedValue()
    let flags = event.flags
    let keyCode = event.getIntegerValueField(.keyboardEventKeycode)

    // Require Cmd+Shift
    guard flags.contains(.maskCommand) && flags.contains(.maskShift) else {
        return Unmanaged.passRetained(event)
    }

    // macOS virtual keycodes: 3→20, 4→21, 5→23
    var action: HotkeyManager.Action? = nil
    switch keyCode {
    case 20: action = .captureFullscreen
    case 21: action = .captureArea
    case 23: action = .captureWindow
    default: break
    }

    if let action = action {
        DispatchQueue.main.async {
            manager.callback?(action)
        }
        return nil // Consume the event
    }

    return Unmanaged.passRetained(event)
}
