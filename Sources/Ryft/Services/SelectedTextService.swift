import AppKit
import ApplicationServices

enum SelectedTextService {
    private struct PasteboardEntry { let values: [(NSPasteboard.PasteboardType, Data)] }

    static func currentSelection(_ completion: @escaping (String?) -> Void) {
        if let selection = accessibilitySelection() { completion(selection); return }
        guard AXIsProcessTrusted() else { completion(nil); return }

        let pasteboard = NSPasteboard.general
        let previous = (pasteboard.pasteboardItems ?? []).map { item in
            PasteboardEntry(values: item.types.compactMap { type in item.data(forType: type).map { (type, $0) } })
        }
        let oldChangeCount = pasteboard.changeCount
        guard let source = CGEventSource(stateID: .combinedSessionState),
              let down = CGEvent(keyboardEventSource: source, virtualKey: 8, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: 8, keyDown: false) else { completion(nil); return }
        down.flags = .maskCommand; up.flags = .maskCommand
        down.post(tap: .cgSessionEventTap); up.post(tap: .cgSessionEventTap)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.14) {
            var selection: String?
            if pasteboard.changeCount != oldChangeCount, let value = pasteboard.string(forType: .string)?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty {
                selection = String(value.prefix(12_000))
            }
            pasteboard.clearContents()
            let restored = previous.map { entry -> NSPasteboardItem in
                let item = NSPasteboardItem()
                entry.values.forEach { item.setData($0.1, forType: $0.0) }
                return item
            }
            if !restored.isEmpty { pasteboard.writeObjects(restored) }
            completion(selection)
        }
    }

    private static func accessibilitySelection() -> String? {
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
