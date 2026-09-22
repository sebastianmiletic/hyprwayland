import AppKit

struct WorkspaceController {
    static func switchTo(_ number: Int) {
        guard (1...9).contains(number) else { return }
        let keyCodes = [18, 19, 20, 21, 23, 22, 26, 28, 25]
        guard let source = CGEventSource(stateID: .hidSystemState),
              let down = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(keyCodes[number - 1]), keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(keyCodes[number - 1]), keyDown: false) else { return }
        down.flags = .maskControl; up.flags = .maskControl
        down.post(tap: .cghidEventTap); up.post(tap: .cghidEventTap)
    }

    static func requestAccessibility() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
    }
}
