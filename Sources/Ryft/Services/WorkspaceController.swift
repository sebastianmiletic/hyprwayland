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
        // Never invoke kAXTrustedCheckOptionPrompt: repeated local builds can
        // otherwise look like unsolicited requests. Permission remains a user
        // decision in the macOS pane opened by this explicit action.
        NSApp.keyWindow?.orderOut(nil)
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") { NSWorkspace.shared.open(url) }
    }
}
