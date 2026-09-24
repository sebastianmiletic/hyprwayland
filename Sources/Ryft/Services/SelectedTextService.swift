import AppKit
import ApplicationServices

enum SelectedTextService {
    static func currentSelection() -> String? {
        guard AXIsProcessTrusted() else { return nil }

        let system = AXUIElementCreateSystemWide()
        if let focused: AXUIElement = attribute(system, kAXFocusedUIElementAttribute as CFString),
           let selection = selectedText(from: focused) {
            return selection
        }

        guard let pid = NSWorkspace.shared.frontmostApplication?.processIdentifier else { return nil }
        let application = AXUIElementCreateApplication(pid)
        if let focused: AXUIElement = attribute(application, kAXFocusedUIElementAttribute as CFString),
           let selection = selectedText(from: focused) {
            return selection
        }
        return nil
    }

    private static func selectedText(from element: AXUIElement) -> String? {
        guard let value: String = attribute(element, kAXSelectedTextAttribute as CFString) else { return nil }
        let selection = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !selection.isEmpty else { return nil }
        return String(selection.prefix(12_000))
    }

    private static func attribute<T>(_ element: AXUIElement, _ name: CFString) -> T? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name, &value) == .success else { return nil }
        return value as? T
    }
}
