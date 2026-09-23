import AppKit
import ApplicationServices
import Combine

/// Ryft-owned automatic Dwindle tiling. The engine intentionally manages one
/// standard window per visible application and remains idle until two distinct
/// applications share a display on the active Mission Control desktop.
final class DwindleTilingService: ObservableObject {
    @Published private(set) var running = false
    @Published private(set) var status = "Automatic tiling is off"
    @Published private(set) var managedApplicationCount = 0

    private struct ManagedWindow {
        let id: CGWindowID
        let pid: pid_t
        let element: AXUIElement
        let frame: CGRect
        let screen: NSScreen
    }

    private struct OriginalWindow {
        let frame: CGRect
        let element: AXUIElement
    }

    private var enabled = false
    private var timer: Timer?
    private var bar = BarConfiguration()
    private var originalWindows: [CGWindowID: OriginalWindow] = [:]
    private var windowOrder: [CGWindowID: Int] = [:]
    private var nextOrder = 0

    func setEnabled(_ value: Bool) {
        enabled = value
        if value {
            running = true
            status = AXIsProcessTrusted() ? "Waiting for a second application" : "Accessibility permission needed"
            startTimer()
            tileVisibleApplications()
        } else {
            restoreVisibleWindows()
            timer?.invalidate(); timer = nil
            running = false
            managedApplicationCount = 0
            status = "Automatic tiling is off"
        }
    }

    func updateBarConfiguration(_ configuration: BarConfiguration) {
        bar = configuration
        if enabled { tileVisibleApplications() }
    }

    func refresh() {
        guard enabled else { return }
        tileVisibleApplications()
    }

    func shutdown() {
        guard enabled else { return }
        restoreVisibleWindows()
        timer?.invalidate(); timer = nil
        enabled = false
    }

    func openAccessibilitySettings() {
        WorkspaceController.requestAccessibility()
    }

    private func startTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 0.45, repeats: true) { [weak self] _ in self?.tileVisibleApplications() }
    }

    private func tileVisibleApplications() {
        guard enabled else { return }
        guard AXIsProcessTrusted() else {
            managedApplicationCount = 0
            status = "Accessibility permission needed"
            return
        }

        let windows = visibleApplicationWindows()
        let grouped = Dictionary(grouping: windows, by: { displayID(for: $0.screen) })
        var tiledIDs = Set<CGWindowID>()
        var tiledApplicationCount = 0

        for (_, displayWindows) in grouped {
            let ordered = displayWindows.sorted { order(for: $0.id) < order(for: $1.id) }
            guard ordered.count >= 2, let screen = ordered.first?.screen else {
                restore(ordered)
                continue
            }

            tiledApplicationCount += ordered.count
            let frames = dwindleFrames(count: ordered.count, in: availableFrame(for: screen))
            for (window, target) in zip(ordered, frames) {
                if originalWindows[window.id] == nil { originalWindows[window.id] = OriginalWindow(frame: window.frame, element: window.element) }
                setFrame(target, for: window.element)
                tiledIDs.insert(window.id)
            }
        }

        // A window that was tiled and is now the only application on its
        // visible display returns to the frame it had before Ryft touched it.
        for window in windows where originalWindows[window.id] != nil && !tiledIDs.contains(window.id) { restore([window]) }
        let existingIDs = allWindowIDs()
        originalWindows = originalWindows.filter { existingIDs.contains($0.key) }
        windowOrder = windowOrder.filter { existingIDs.contains($0.key) }

        managedApplicationCount = tiledApplicationCount
        status = tiledApplicationCount >= 2 ? "Tiling \(tiledApplicationCount) applications" : "Waiting for a second application"
    }

    private func allWindowIDs() -> Set<CGWindowID> {
        guard let list = CGWindowListCopyWindowInfo([.optionAll, .excludeDesktopElements], kCGNullWindowID) as? [[CFString: Any]] else { return [] }
        return Set(list.compactMap { ($0[kCGWindowNumber] as? NSNumber).map { CGWindowID($0.uint32Value) } })
    }

    private func visibleApplicationWindows() -> [ManagedWindow] {
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let list = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[CFString: Any]] else { return [] }
        let ownPID = ProcessInfo.processInfo.processIdentifier
        var seenPIDs = Set<pid_t>()
        var result: [ManagedWindow] = []

        for info in list {
            guard let pidNumber = info[kCGWindowOwnerPID] as? NSNumber,
                  let layer = info[kCGWindowLayer] as? NSNumber,
                  let boundsDictionary = info[kCGWindowBounds] as? NSDictionary,
                  let cgFrame = CGRect(dictionaryRepresentation: boundsDictionary),
                  let windowNumber = info[kCGWindowNumber] as? NSNumber else { continue }
            let pid = pidNumber.int32Value
            guard pid != ownPID, layer.intValue == 0, !seenPIDs.contains(pid), cgFrame.width >= 180, cgFrame.height >= 100 else { continue }
            guard let match = accessibleWindow(for: pid, closestTo: cgFrame), let screen = screen(containing: cgFrame) else { continue }
            seenPIDs.insert(pid)
            result.append(ManagedWindow(id: CGWindowID(windowNumber.uint32Value), pid: pid, element: match.element, frame: match.frame, screen: screen))
        }
        return result
    }

    private func accessibleWindow(for pid: pid_t, closestTo target: CGRect) -> (element: AXUIElement, frame: CGRect)? {
        let application = AXUIElementCreateApplication(pid)
        guard let windows: [AXUIElement] = attribute(application, kAXWindowsAttribute as CFString) else { return nil }
        var best: (AXUIElement, CGRect, CGFloat)?

        for window in windows {
            guard (attribute(window, kAXRoleAttribute as CFString) as String?) == (kAXWindowRole as String),
                  (attribute(window, kAXSubroleAttribute as CFString) as String?) == (kAXStandardWindowSubrole as String),
                  attribute(window, kAXMinimizedAttribute as CFString) as Bool? != true,
                  attribute(window, "AXFullScreen" as CFString) as Bool? != true,
                  isSettable(kAXPositionAttribute as CFString, on: window),
                  isSettable(kAXSizeAttribute as CFString, on: window),
                  let frame = frame(of: window) else { continue }
            let distance = abs(frame.minX - target.minX) + abs(frame.minY - target.minY) + abs(frame.width - target.width) + abs(frame.height - target.height)
            if best == nil || distance < best!.2 { best = (window, frame, distance) }
        }
        guard let best, best.2 < 180 else { return nil }
        return (best.0, best.1)
    }

    private func isSettable(_ attribute: CFString, on element: AXUIElement) -> Bool {
        var settable = DarwinBoolean(false)
        return AXUIElementIsAttributeSettable(element, attribute, &settable) == .success && settable.boolValue
    }

    private func frame(of element: AXUIElement) -> CGRect? {
        guard let positionValue: AXValue = attribute(element, kAXPositionAttribute as CFString),
              let sizeValue: AXValue = attribute(element, kAXSizeAttribute as CFString) else { return nil }
        var point = CGPoint.zero; var size = CGSize.zero
        guard AXValueGetValue(positionValue, .cgPoint, &point), AXValueGetValue(sizeValue, .cgSize, &size) else { return nil }
        return CGRect(origin: point, size: size)
    }

    private func attribute<T>(_ element: AXUIElement, _ name: CFString) -> T? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name, &value) == .success else { return nil }
        return value as? T
    }

    private func setFrame(_ frame: CGRect, for element: AXUIElement) {
        guard let current = self.frame(of: element), frameDifference(current, frame) > 2 else { return }
        var point = frame.origin; var size = frame.size
        guard let positionValue = AXValueCreate(.cgPoint, &point), let sizeValue = AXValueCreate(.cgSize, &size) else { return }
        // Some applications constrain size based on their current position.
        // Position, size, then position once more gives those apps a stable fit.
        AXUIElementSetAttributeValue(element, kAXPositionAttribute as CFString, positionValue)
        AXUIElementSetAttributeValue(element, kAXSizeAttribute as CFString, sizeValue)
        AXUIElementSetAttributeValue(element, kAXPositionAttribute as CFString, positionValue)
    }

    private func frameDifference(_ lhs: CGRect, _ rhs: CGRect) -> CGFloat {
        max(abs(lhs.minX - rhs.minX), abs(lhs.minY - rhs.minY), abs(lhs.width - rhs.width), abs(lhs.height - rhs.height))
    }

    private func restore(_ windows: [ManagedWindow]) {
        for window in windows {
            guard let original = originalWindows.removeValue(forKey: window.id) else { continue }
            setFrame(original.frame, for: original.element)
        }
    }

    private func restoreVisibleWindows() {
        for original in originalWindows.values { setFrame(original.frame, for: original.element) }
        originalWindows.removeAll()
        windowOrder.removeAll()
    }

    private func order(for id: CGWindowID) -> Int {
        if let order = windowOrder[id] { return order }
        let order = nextOrder; nextOrder += 1; windowOrder[id] = order
        return order
    }

    private func screen(containing frame: CGRect) -> NSScreen? {
        NSScreen.screens.max { lhs, rhs in
            intersectionArea(frame, displayBounds(for: lhs)) < intersectionArea(frame, displayBounds(for: rhs))
        }.flatMap { intersectionArea(frame, displayBounds(for: $0)) > 0 ? $0 : nil }
    }

    private func intersectionArea(_ lhs: CGRect, _ rhs: CGRect) -> CGFloat {
        let intersection = lhs.intersection(rhs)
        return intersection.isNull ? 0 : intersection.width * intersection.height
    }

    private func displayID(for screen: NSScreen) -> CGDirectDisplayID {
        (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0
    }

    private func displayBounds(for screen: NSScreen) -> CGRect {
        CGDisplayBounds(displayID(for: screen))
    }

    private func availableFrame(for screen: NSScreen) -> CGRect {
        let display = displayBounds(for: screen)
        let mainMaxY = CGDisplayBounds(CGMainDisplayID()).maxY
        let visible = screen.visibleFrame
        let visibleTop = mainMaxY - visible.maxY
        let visibleBottom = mainMaxY - visible.minY
        var frame = CGRect(
            x: max(display.minX, visible.minX),
            y: max(display.minY, visibleTop),
            width: min(display.maxX, visible.maxX) - max(display.minX, visible.minX),
            height: min(display.maxY, visibleBottom) - max(display.minY, visibleTop)
        )

        let shouldReserveBar = bar.enabled && (bar.showOnAllDisplays || screen == NSScreen.main)
        if shouldReserveBar {
            let insets = bar.presentation == .top ? 0 : bar.outerInset * 2
            let shelf: CGFloat
            if bar.notchMaskEnabled {
                shelf = bar.notchMaskHeight > 0 ? bar.notchMaskHeight : ((screen.auxiliaryTopLeftArea != nil || screen.auxiliaryTopRightArea != nil) ? max(screen.safeAreaInsets.top, 32) : 0)
            } else { shelf = 0 }
            let barBottom = display.minY + bar.height + insets + shelf
            let removed = max(0, barBottom - frame.minY)
            frame.origin.y += removed; frame.size.height -= removed
        }
        return frame.insetBy(dx: 8, dy: 8)
    }

    private func dwindleFrames(count: Int, in frame: CGRect) -> [CGRect] {
        guard count > 1 else { return [frame] }
        var result: [CGRect] = []
        var remainder = frame
        let gap: CGFloat = 10
        for index in 0..<count {
            let remaining = count - index
            if remaining == 1 { result.append(remainder); break }
            if remainder.width * 1.15 >= remainder.height {
                let firstWidth = (remainder.width - gap) / 2
                result.append(CGRect(x: remainder.minX, y: remainder.minY, width: firstWidth, height: remainder.height))
                remainder = CGRect(x: remainder.minX + firstWidth + gap, y: remainder.minY, width: remainder.width - firstWidth - gap, height: remainder.height)
            } else {
                let firstHeight = (remainder.height - gap) / 2
                result.append(CGRect(x: remainder.minX, y: remainder.minY, width: remainder.width, height: firstHeight))
                remainder = CGRect(x: remainder.minX, y: remainder.minY + firstHeight + gap, width: remainder.width, height: remainder.height - firstHeight - gap)
            }
        }
        return result
    }
}
