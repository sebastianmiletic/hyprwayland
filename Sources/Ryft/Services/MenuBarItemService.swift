import AppKit
import ApplicationServices
import Combine

struct RyftMenuBarItem: Identifiable {
    let id = UUID()
    let title: String
    let applicationName: String
    let icon: NSImage?
    fileprivate let element: AXUIElement
}

/// Accessibility bridge for third-party status items that would normally live
/// in Apple's hidden menu bar. Ryft presents only the launcher surface; pressing
/// an item invokes its original AX action, so the owning app still renders and
/// controls its own menu or popover.
final class MenuBarItemService: ObservableObject {
    @Published private(set) var items: [RyftMenuBarItem] = []
    @Published private(set) var status = ""

    func refresh() {
        guard AXIsProcessTrusted() else {
            items = []; status = "Accessibility is required to use menu-bar apps."
            return
        }
        var found: [RyftMenuBarItem] = []
        var seen = Set<String>()
        for app in NSWorkspace.shared.runningApplications where app.processIdentifier != ProcessInfo.processInfo.processIdentifier {
            let root = AXUIElementCreateApplication(app.processIdentifier)
            guard let extras: AXUIElement = attribute(root, "AXExtrasMenuBar" as CFString) else { continue }
            for element in descendants(of: extras) {
                let role: String = attribute(element, kAXRoleAttribute as CFString) ?? ""
                guard role == (kAXMenuBarItemRole as String) else { continue }
                let title: String = attribute(element, kAXTitleAttribute as CFString) ?? ""
                let description: String = attribute(element, kAXDescriptionAttribute as CFString) ?? ""
                let help: String = attribute(element, kAXHelpAttribute as CFString) ?? ""
                let appName = app.localizedName ?? "Menu bar app"
                let label = [title, description, help].first { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty } ?? appName
                let key = "\(app.processIdentifier):\(label)"
                guard seen.insert(key).inserted else { continue }
                let icon = app.bundleURL.map { NSWorkspace.shared.icon(forFile: $0.path) }
                found.append(RyftMenuBarItem(title: label, applicationName: appName, icon: icon, element: element))
            }
        }
        items = found.sorted { $0.applicationName.localizedCaseInsensitiveCompare($1.applicationName) == .orderedAscending }
        status = items.isEmpty ? "No menu-bar apps are currently available." : ""
    }

    func activate(_ item: RyftMenuBarItem) {
        guard AXUIElementPerformAction(item.element, kAXPressAction as CFString) == .success else {
            status = "\(item.applicationName) did not expose an interactive status item."
            return
        }
        status = ""
    }

    private func descendants(of root: AXUIElement) -> [AXUIElement] {
        var result: [AXUIElement] = []
        var queue = [root]
        var visited = Set<CFHashCode>()
        while !queue.isEmpty, result.count < 160 {
            let element = queue.removeFirst()
            guard visited.insert(CFHash(element)).inserted else { continue }
            result.append(element)
            let children: [AXUIElement] = attribute(element, kAXChildrenAttribute as CFString) ?? []
            queue.append(contentsOf: children)
        }
        return result
    }

    private func attribute<T>(_ element: AXUIElement, _ name: CFString) -> T? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name, &value) == .success else { return nil }
        return value as? T
    }
}
