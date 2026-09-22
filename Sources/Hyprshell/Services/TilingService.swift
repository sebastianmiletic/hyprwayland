import AppKit
import ApplicationServices
import Combine

/// Event-driven Hyprland-style tiling using only the public macOS Accessibility
/// and Core Graphics window APIs. Disabling it stops all window management.
final class TilingService: ObservableObject {
    @Published private(set) var status = "Tiling is off"
    @Published private(set) var managedWindowCount = 0
    @Published private(set) var hasAccessibility = AXIsProcessTrusted()

    private var configuration = TilingConfiguration()
    private var workspaceObservers: [NSObjectProtocol] = []
    private var accessibilityObservers: [pid_t: AXObserver] = [:]
    private var pollTimer: Timer?
    private var permissionTimer: Timer?
    private var pendingReflow: DispatchWorkItem?
    private var windowOrder: [WindowIdentity] = []
    private var isApplyingLayout = false

    init() {
        let center = NSWorkspace.shared.notificationCenter
        workspaceObservers.append(center.addObserver(forName: NSWorkspace.didLaunchApplicationNotification, object: nil, queue: .main) { [weak self] note in
            if let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication { self?.observe(app) }
            self?.scheduleReflow(delay: 0.03)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.14) { self?.scheduleReflow(delay: 0) }
        })
        workspaceObservers.append(center.addObserver(forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: .main) { [weak self] note in
            if let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication { self?.accessibilityObservers.removeValue(forKey: app.processIdentifier) }
            self?.scheduleReflow(delay: 0.08)
        })
        workspaceObservers.append(center.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] _ in self?.scheduleReflow(delay: 0.015) })
        workspaceObservers.append(NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in self?.scheduleReflow(delay: 0.15) })
    }

    deinit {
        workspaceObservers.forEach { NotificationCenter.default.removeObserver($0); NSWorkspace.shared.notificationCenter.removeObserver($0) }
        permissionTimer?.invalidate()
        stopManaging()
    }

    func update(_ configuration: TilingConfiguration) {
        let wasManaging = isAutomatic
        self.configuration = configuration
        hasAccessibility = AXIsProcessTrusted()
        if isAutomatic {
            if !hasAccessibility {
                stopManaging(); waitForAccessibility(); status = "Accessibility permission required"
            } else {
                startManaging()
                status = "Hyprland tiling active"
                scheduleReflow(delay: wasManaging ? 0.08 : 0.2)
            }
        } else {
            permissionTimer?.invalidate(); permissionTimer = nil
            stopManaging()
            status = "Tiling is off"
        }
    }

    func toggleAutoTile() {
        configuration.enabled.toggle()
        configuration.autoTile = configuration.enabled
        update(configuration)
    }

    func requestAccessibility() {
        guard !AXIsProcessTrusted() else { hasAccessibility = true; startManaging(); scheduleReflow(delay: 0.05); return }
        WorkspaceController.requestAccessibility()
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
            self?.hasAccessibility = AXIsProcessTrusted()
            if self?.hasAccessibility == true { self?.startManaging(); self?.scheduleReflow(delay: 0.1) }
        }
    }

    func tileNow() {
        guard AXIsProcessTrusted() else { hasAccessibility = false; status = "Accessibility permission required"; return }
        guard configuration.enabled else { status = "Enable tiling first"; return }
        reflow()
    }

    func focusNext() {
        guard AXIsProcessTrusted() else { hasAccessibility = false; status = "Accessibility permission required"; return }
        let windows = visibleTileableWindows()
        guard windows.count > 1 else { return }
        let focused = focusedWindow()
        let index = focused.flatMap { current in windows.firstIndex { CFEqual($0.element, current) } } ?? -1
        let next = windows[(index + 1) % windows.count].element
        AXUIElementPerformAction(next, kAXRaiseAction as CFString)
        AXUIElementSetAttributeValue(next, kAXMainAttribute as CFString, kCFBooleanTrue)
        status = "Focused next window"
    }

    private var isAutomatic: Bool { configuration.enabled }

    private func waitForAccessibility() {
        guard configuration.enabled, permissionTimer == nil else { return }
        permissionTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] timer in
            guard let self else { return }
            guard self.configuration.enabled else { timer.invalidate(); self.permissionTimer = nil; return }
            guard AXIsProcessTrusted() else { return }
            timer.invalidate(); self.permissionTimer = nil; self.hasAccessibility = true
            self.startManaging(); self.scheduleReflow(delay: 0.05)
        }
    }

    private func startManaging() {
        guard isAutomatic, AXIsProcessTrusted() else { return }
        permissionTimer?.invalidate(); permissionTimer = nil; hasAccessibility = true
        for app in NSWorkspace.shared.runningApplications { observe(app) }
        if pollTimer == nil {
            pollTimer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] _ in
                guard let self, self.isAutomatic, !self.isApplyingLayout else { return }
                let count = self.visibleTileableWindows().count
                if count != self.managedWindowCount { self.scheduleReflow(delay: 0.05) }
            }
        }
    }

    private func stopManaging() {
        pollTimer?.invalidate(); pollTimer = nil
        pendingReflow?.cancel(); pendingReflow = nil
        accessibilityObservers.removeAll()
        managedWindowCount = 0
    }

    private func observe(_ app: NSRunningApplication) {
        guard isAutomatic, app.activationPolicy == .regular, app.processIdentifier != ProcessInfo.processInfo.processIdentifier,
              !configuration.ignoredBundleIDs.contains(app.bundleIdentifier ?? ""), accessibilityObservers[app.processIdentifier] == nil else { return }
        var observer: AXObserver?
        let result = AXObserverCreate(app.processIdentifier, { _, _, _, refcon in
            guard let refcon else { return }
            let service = Unmanaged<TilingService>.fromOpaque(refcon).takeUnretainedValue()
            DispatchQueue.main.async {
                service.scheduleReflow(delay: 0.02)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { service.scheduleReflow(delay: 0) }
            }
        }, &observer)
        guard result == .success, let observer else { return }
        let application = AXUIElementCreateApplication(app.processIdentifier)
        let pointer = Unmanaged.passUnretained(self).toOpaque()
        AXObserverAddNotification(observer, application, kAXWindowCreatedNotification as CFString, pointer)
        AXObserverAddNotification(observer, application, kAXFocusedWindowChangedNotification as CFString, pointer)
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .commonModes)
        accessibilityObservers[app.processIdentifier] = observer
    }

    private func scheduleReflow(delay: TimeInterval) {
        guard isAutomatic else { return }
        pendingReflow?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.reflow() }
        pendingReflow = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    private func reflow() {
        guard configuration.enabled, AXIsProcessTrusted(), !isApplyingLayout else { return }
        let windows = visibleTileableWindows()
        managedWindowCount = windows.count
        guard !windows.isEmpty else { status = isAutomatic ? "Hyprland tiling active · no windows" : "No tileable windows"; return }

        let live = Set(windows.map(\.identity))
        windowOrder.removeAll { !live.contains($0) }
        for window in windows where !windowOrder.contains(window.identity) { windowOrder.append(window.identity) }
        let ordered = windows.sorted { (windowOrder.firstIndex(of: $0.identity) ?? .max) < (windowOrder.firstIndex(of: $1.identity) ?? .max) }

        let primaryTop = NSScreen.screens.first?.frame.maxY ?? 0
        let groups = Dictionary(grouping: ordered) { screen(containing: $0.frame, primaryTop: primaryTop)?.localizedName ?? "main" }
        isApplyingLayout = true
        for group in groups.values {
            guard let first = group.first, let screen = screen(containing: first.frame, primaryTop: primaryTop) else { continue }
            let frames = layoutFrames(count: group.count, in: screen.visibleFrame)
            for (window, frame) in zip(group, frames) { set(window: window.element, frame: frame, primaryTop: primaryTop) }
        }
        isApplyingLayout = false
        status = "Hyprland tiled \(windows.count) window\(windows.count == 1 ? "" : "s")"
    }

    private struct WindowIdentity: Hashable { let pid: pid_t; let windowNumber: Int }
    private struct ManagedWindow {
        let element: AXUIElement
        let identity: WindowIdentity
        let frame: CGRect
    }

    /// CGWindowList's on-screen filter limits management to the current Space.
    /// AX alone also returns windows from hidden Mission Control Spaces.
    private struct OnScreenWindow {
        let pid: pid_t
        let number: Int
        let title: String
        let frame: CGRect
    }

    private func visibleTileableWindows() -> [ManagedWindow] {
        let ownPID = ProcessInfo.processInfo.processIdentifier
        let info = (CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]]) ?? []
        let onScreen: [OnScreenWindow] = info.compactMap { value in
            guard (value[kCGWindowLayer as String] as? NSNumber)?.intValue == 0,
                  let pid = (value[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value,
                  let number = (value[kCGWindowNumber as String] as? NSNumber)?.intValue,
                  let bounds = value[kCGWindowBounds as String] as? [String: Any],
                  let frame = CGRect(dictionaryRepresentation: bounds as CFDictionary), frame.width > 80, frame.height > 60 else { return nil }
            return OnScreenWindow(pid: pid, number: number, title: value[kCGWindowName as String] as? String ?? "", frame: frame)
        }
        let visiblePIDs = Set(onScreen.map(\.pid))
        return NSWorkspace.shared.runningApplications
            .filter { visiblePIDs.contains($0.processIdentifier) && $0.processIdentifier != ownPID && $0.activationPolicy == .regular && !configuration.ignoredBundleIDs.contains($0.bundleIdentifier ?? "") }
            .flatMap { app -> [ManagedWindow] in
                let application = AXUIElementCreateApplication(app.processIdentifier)
                var value: CFTypeRef?
                guard AXUIElementCopyAttributeValue(application, kAXWindowsAttribute as CFString, &value) == .success, let windows = value as? [AXUIElement] else { return [] }
                var claimed = Set<Int>()
                return windows.compactMap { window in
                    guard isTileable(window), let frame = frameAttribute(window) else { return nil }
                    let title = stringAttribute(window, kAXTitleAttribute as String) ?? ""
                    let match = onScreen.filter { $0.pid == app.processIdentifier && !claimed.contains($0.number) }.max { lhs, rhs in
                        matchScore(axFrame: frame, axTitle: title, candidate: lhs) < matchScore(axFrame: frame, axTitle: title, candidate: rhs)
                    }
                    guard let match, matchScore(axFrame: frame, axTitle: title, candidate: match) > 0.18 else { return nil }
                    claimed.insert(match.number)
                    return ManagedWindow(element: window, identity: WindowIdentity(pid: app.processIdentifier, windowNumber: match.number), frame: frame)
                }
            }
    }

    private func matchScore(axFrame: CGRect, axTitle: String, candidate: OnScreenWindow) -> Double {
        let intersection = axFrame.intersection(candidate.frame)
        let overlap = intersection.isNull ? 0 : (intersection.width * intersection.height) / max(1, min(axFrame.width * axFrame.height, candidate.frame.width * candidate.frame.height))
        let titleBonus = !axTitle.isEmpty && axTitle == candidate.title ? 1.0 : 0.0
        return Double(overlap) + titleBonus
    }

    private func isTileable(_ window: AXUIElement) -> Bool {
        if boolAttribute(window, kAXMinimizedAttribute as String) == true || boolAttribute(window, "AXFullScreen") == true { return false }
        guard stringAttribute(window, kAXRoleAttribute as String) == (kAXWindowRole as String) else { return false }
        let subrole = stringAttribute(window, kAXSubroleAttribute as String)
        guard subrole == nil || subrole == (kAXStandardWindowSubrole as String) else { return false }
        var settable = DarwinBoolean(false)
        guard AXUIElementIsAttributeSettable(window, kAXPositionAttribute as CFString, &settable) == .success, settable.boolValue else { return false }
        guard AXUIElementIsAttributeSettable(window, kAXSizeAttribute as CFString, &settable) == .success, settable.boolValue else { return false }
        return true
    }

    private func focusedWindow() -> AXUIElement? {
        let system = AXUIElementCreateSystemWide(); var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(system, kAXFocusedWindowAttribute as CFString, &value) == .success else { return nil }
        return value as! AXUIElement?
    }

    private func screen(containing axFrame: CGRect, primaryTop: CGFloat) -> NSScreen? {
        let cocoaCenter = CGPoint(x: axFrame.midX, y: primaryTop - axFrame.midY)
        return NSScreen.screens.first { $0.frame.contains(cocoaCenter) } ?? NSScreen.main
    }

    private func layoutFrames(count: Int, in visible: NSRect) -> [NSRect] {
        let outer = configuration.outerGap, inner = configuration.innerGap
        let area = visible.insetBy(dx: outer, dy: outer)
        guard count > 1 else { return [area] }
        switch configuration.layout {
        case .dwindle: return dwindleFrames(count: count, area: area, gap: inner)
        case .monocle: return Array(repeating: area, count: count)
        case .columns:
            let width = (area.width - inner * Double(count - 1)) / Double(count)
            return (0..<count).map { NSRect(x: area.minX + Double($0) * (width + inner), y: area.minY, width: width, height: area.height) }
        case .grid:
            let columns = Int(ceil(sqrt(Double(count)))), rows = Int(ceil(Double(count) / Double(columns)))
            let width = (area.width - inner * Double(columns - 1)) / Double(columns), height = (area.height - inner * Double(rows - 1)) / Double(rows)
            return (0..<count).map { index in
                let col = index % columns, row = index / columns
                return NSRect(x: area.minX + Double(col) * (width + inner), y: area.maxY - Double(row + 1) * height - Double(row) * inner, width: width, height: height)
            }
        case .masterStack:
            let masterWidth = (area.width - inner) * configuration.masterRatio
            let stackWidth = area.width - inner - masterWidth
            let stackHeight = (area.height - inner * Double(count - 2)) / Double(count - 1)
            var frames = [NSRect(x: area.minX, y: area.minY, width: masterWidth, height: area.height)]
            frames += (0..<(count - 1)).map { NSRect(x: area.minX + masterWidth + inner, y: area.maxY - Double($0 + 1) * stackHeight - Double($0) * inner, width: stackWidth, height: stackHeight) }
            return frames
        }
    }

    /// Hyprland's dwindle behavior: each new client recursively splits the
    /// remaining leaf, choosing the leaf's longest axis.
    private func dwindleFrames(count: Int, area: CGRect, gap: CGFloat) -> [CGRect] {
        guard count > 1 else { return [area] }
        var result: [CGRect] = []
        var remaining = area
        for index in 0..<(count - 1) {
            if remaining.width >= remaining.height {
                let width = (remaining.width - gap) / 2
                result.append(CGRect(x: remaining.minX, y: remaining.minY, width: width, height: remaining.height))
                remaining = CGRect(x: remaining.minX + width + gap, y: remaining.minY, width: width, height: remaining.height)
            } else {
                let height = (remaining.height - gap) / 2
                result.append(CGRect(x: remaining.minX, y: remaining.maxY - height, width: remaining.width, height: height))
                remaining = CGRect(x: remaining.minX, y: remaining.minY, width: remaining.width, height: height)
            }
            if index == count - 2 { result.append(remaining) }
        }
        return result
    }

    private func set(window: AXUIElement, frame: NSRect, primaryTop: CGFloat) {
        var point = CGPoint(x: frame.minX.rounded(), y: (primaryTop - frame.maxY).rounded())
        var size = CGSize(width: frame.width.rounded(), height: frame.height.rounded())
        if let p = AXValueCreate(.cgPoint, &point) { AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, p) }
        if let s = AXValueCreate(.cgSize, &size) { AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, s) }
        if let p = AXValueCreate(.cgPoint, &point) { AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, p) }
    }

    private func frameAttribute(_ element: AXUIElement) -> CGRect? {
        guard let point = pointAttribute(element, kAXPositionAttribute as String), let size = sizeAttribute(element, kAXSizeAttribute as String) else { return nil }
        return CGRect(origin: point, size: size)
    }
    private func pointAttribute(_ element: AXUIElement, _ attribute: String) -> CGPoint? {
        var value: CFTypeRef?; guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success, let ax = value as! AXValue? else { return nil }
        var point = CGPoint.zero; return AXValueGetValue(ax, .cgPoint, &point) ? point : nil
    }
    private func sizeAttribute(_ element: AXUIElement, _ attribute: String) -> CGSize? {
        var value: CFTypeRef?; guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success, let ax = value as! AXValue? else { return nil }
        var size = CGSize.zero; return AXValueGetValue(ax, .cgSize, &size) ? size : nil
    }
    private func stringAttribute(_ element: AXUIElement, _ attribute: String) -> String? {
        var value: CFTypeRef?; guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return nil }
        return value as? String
    }
    private func boolAttribute(_ element: AXUIElement, _ attribute: String) -> Bool? {
        var value: CFTypeRef?; guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return nil }
        return value as? Bool
    }
}
