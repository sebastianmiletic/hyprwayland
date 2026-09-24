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

    static func requestAccessibility() { openPrivacyPane("Privacy_Accessibility") }

    static func openPrivacyPane(_ pane: String) {
        openSystemSettings([
            "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?\(pane)",
            "x-apple.systempreferences:com.apple.preference.security?\(pane)"
        ])
    }

    static func openNotifications() {
        openSystemSettings([
            "x-apple.systempreferences:com.apple.Notifications-Settings.extension",
            "x-apple.systempreferences:com.apple.preference.notifications"
        ])
    }

    static func openMissionControlShortcuts() {
        openSystemSettings([
            "x-apple.systempreferences:com.apple.Keyboard-Settings.extension?Shortcuts",
            "x-apple.systempreferences:com.apple.preference.keyboard?Shortcuts"
        ])
    }

    private static func openSystemSettings(_ candidates: [String]) {
        let urls = candidates.compactMap(URL.init(string:))
        guard let first = urls.first else { return }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.open(first, configuration: configuration) { _, error in
            if error != nil, let fallback = urls.dropFirst().first {
                NSWorkspace.shared.open(fallback)
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.systempreferences").first?.activate(options: [.activateAllWindows])
            }
        }
    }
}
