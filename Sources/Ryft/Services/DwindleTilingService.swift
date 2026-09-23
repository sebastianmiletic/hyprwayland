import AppKit
import ApplicationServices
import Combine
import QuartzCore

/// Ryft-owned automatic Dwindle tiling. The engine manages one standard window
/// per visible application. A single application fills the safe work area;
/// additional applications recursively split that same area.
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

    private struct FrameAnimation {
        let element: AXUIElement
        let from: CGRect
        let to: CGRect
        let startedAt: CFTimeInterval
        let duration: CFTimeInterval
    }

    private var enabled = false
    private var timer: Timer?
    private var animationTimer: Timer?
    private var animations: [CGWindowID: FrameAnimation] = [:]
    private var bar = BarConfiguration()
    private var configuration = TilingConfiguration()
    private var originalWindows: [CGWindowID: OriginalWindow] = [:]
    private var windowOrder: [CGWindowID: Int] = [:]
    private var nextOrder = 0

    func setEnabled(_ value: Bool) {
        enabled = value
        if value {
            running = true
            status = AXIsProcessTrusted() ? "Waiting for an application" : "Accessibility permission needed"
            startTimer()
            tileVisibleApplications()
        } else {
            restoreManagedWindows(animated: true)
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

    func updateConfiguration(_ configuration: TilingConfiguration) {
        self.configuration = configuration
        if enabled { tileVisibleApplications() }
    }

    func refresh() {
        guard enabled else { return }
        tileVisibleApplications()
    }

    func shutdown() {
        guard enabled else { return }
        restoreManagedWindows(animated: false)
        timer?.invalidate(); timer = nil
        animationTimer?.invalidate(); animationTimer = nil
        animations.removeAll()
        enabled = false
    }

    func openAccessibilitySettings() {
        WorkspaceController.requestAccessibility()
    }

    private func startTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in self?.tileVisibleApplications() }
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
            guard let screen = ordered.first?.screen else { continue }

            tiledApplicationCount += ordered.count
            let frames = dwindleFrames(count: ordered.count, in: availableFrame(for: screen))
            for (window, target) in zip(ordered, frames) {
                if originalWindows[window.id] == nil { originalWindows[window.id] = OriginalWindow(frame: window.frame, element: window.element) }
                setFrame(target, for: window.element, id: window.id)
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
        switch tiledApplicationCount {
        case 0: status = "Waiting for an application"
        case 1: status = "Filling the display with 1 application"
        default: status = "Tiling \(tiledApplicationCount) applications"
        }
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
            if let bundleID = NSRunningApplication(processIdentifier: pid)?.bundleIdentifier, configuration.excludedBundleIdentifiers.contains(bundleID) { continue }
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
        guard let best else { return nil }
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

    private func setFrame(_ target: CGRect, for element: AXUIElement, id: CGWindowID, animated: Bool = true) {
        if animated, let animation = animations[id], frameDifference(animation.to, target) < 1 { return }
        guard let current = frame(of: element), frameDifference(current, target) > 1 else {
            animations.removeValue(forKey: id)
            return
        }
        guard animated, !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else {
            animations.removeValue(forKey: id)
            applyFrame(target, to: element)
            return
        }
        animations[id] = FrameAnimation(element: element, from: current, to: target.integral, startedAt: CACurrentMediaTime(), duration: 0.20)
        startAnimationTimerIfNeeded()
    }

    private func startAnimationTimerIfNeeded() {
        guard animationTimer == nil else { return }
        let timer = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in self?.advanceAnimations() }
        RunLoop.main.add(timer, forMode: .common)
        animationTimer = timer
    }

    private func advanceAnimations() {
        let now = CACurrentMediaTime()
        var completed: [CGWindowID] = []
        for (id, animation) in animations {
            let progress = min(1, max(0, (now - animation.startedAt) / animation.duration))
            let eased = 1 - pow(1 - progress, 5) // decisive ease-out-quint
            let frame = interpolate(from: animation.from, to: animation.to, progress: CGFloat(eased))
            applyFrame(frame, to: animation.element)
            if progress >= 1 { completed.append(id) }
        }
        for id in completed { animations.removeValue(forKey: id) }
        if animations.isEmpty { animationTimer?.invalidate(); animationTimer = nil }
    }

    private func interpolate(from: CGRect, to: CGRect, progress: CGFloat) -> CGRect {
        CGRect(
            x: from.minX + (to.minX - from.minX) * progress,
            y: from.minY + (to.minY - from.minY) * progress,
            width: from.width + (to.width - from.width) * progress,
            height: from.height + (to.height - from.height) * progress
        )
    }

    private func applyFrame(_ frame: CGRect, to element: AXUIElement) {
        var point = frame.origin; var size = frame.size
        guard let positionValue = AXValueCreate(.cgPoint, &point), let sizeValue = AXValueCreate(.cgSize, &size) else { return }
        // Move before resizing so AppKit does not briefly grow the window from
        // its old top edge. Reasserting position after size handles apps that
        // apply minimum-size constraints without producing a visible jump.
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
            setFrame(original.frame, for: original.element, id: window.id)
        }
    }

    private func restoreManagedWindows(animated: Bool) {
        for (id, original) in originalWindows { setFrame(original.frame, for: original.element, id: id, animated: animated) }
        originalWindows.removeAll()
        windowOrder.removeAll()
    }

    private func order(for id: CGWindowID) -> Int {
        if let order = windowOrder[id] { return order }
        let order = nextOrder; nextOrder += 1; windowOrder[id] = order
        return order
    }

    private func screen(containing frame: CGRect) -> NSScreen? {
        // CG can briefly report a visible window just beyond an edge while a
        // Space or application transition settles. Keep it assigned to the
        // nearest display so the next layout frame clamps it safely on-screen.
        NSScreen.screens.max { lhs, rhs in
            screenScore(for: lhs, window: frame) < screenScore(for: rhs, window: frame)
        }
    }

    private func screenScore(for screen: NSScreen, window: CGRect) -> CGFloat {
        let bounds = displayBounds(for: screen)
        let overlap = intersectionArea(window, bounds)
        if overlap > 0 { return 1_000_000_000 + overlap }
        let dx = window.midX - bounds.midX
        let dy = window.midY - bounds.midY
        return -(dx * dx + dy * dy)
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
        let gap = max(0, min(configuration.outerGap, 40))
        return frame.insetBy(dx: gap, dy: gap)
    }

    private func dwindleFrames(count: Int, in frame: CGRect) -> [CGRect] {
        guard count > 1 else { return [frame] }
        var result: [CGRect] = []
        var remainder = frame
        let gap = max(0, min(configuration.gap, 40))
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
