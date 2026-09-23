import AppKit
import Combine
import Darwin

struct WorkspaceApplication: Equatable {
    let name: String
    let bundlePath: String
}

/// Tracks the actual current Mission Control desktop. macOS exposes the change
/// notification publicly but not the desktop index, so Ryft reads the same
/// ordered Space metadata used by Dock through dynamically resolved SkyLight
/// symbols. It falls back to tracked keyboard navigation if Apple changes it.
final class WorkspaceService: ObservableObject {
    @Published private(set) var currentDesktop = 1
    @Published private(set) var desktopCount = 1
    @Published private(set) var canReadSpaces = false
    @Published private(set) var desktopApplications: [Int: WorkspaceApplication] = [:]
    var experimentalTransitionsEnabled = true

    private let transitionController = WorkspaceTransitionController()
    private typealias MainConnection = @convention(c) () -> UInt32
    private typealias CopySpaces = @convention(c) (UInt32) -> Unmanaged<CFArray>?
    private typealias SetCurrentSpace = @convention(c) (UInt32, CFString, UInt64) -> Int32
    private typealias CopyWindows = @convention(c) (UInt32, UInt32, CFArray, UInt32, UnsafePointer<UInt64>?, UnsafePointer<UInt64>?) -> Unmanaged<CFArray>?
    private let library: UnsafeMutableRawPointer?
    private let mainConnection: MainConnection?
    private let copySpaces: CopySpaces?
    private let setCurrentSpace: SetCurrentSpace?
    private let copyWindows: CopyWindows?
    private var observers: [NSObjectProtocol] = []
    private var refreshTimer: DispatchSourceTimer?
    private var lastApplicationRefresh = Date.distantPast
    private let iconCache = NSCache<NSString, NSImage>()

    init() {
        library = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_LAZY)
        if let library, let symbol = dlsym(library, "CGSMainConnectionID") { mainConnection = unsafeBitCast(symbol, to: MainConnection.self) } else { mainConnection = nil }
        if let library, let symbol = dlsym(library, "CGSCopyManagedDisplaySpaces") { copySpaces = unsafeBitCast(symbol, to: CopySpaces.self) } else { copySpaces = nil }
        if let library, let symbol = dlsym(library, "CGSManagedDisplaySetCurrentSpace") { setCurrentSpace = unsafeBitCast(symbol, to: SetCurrentSpace.self) } else { setCurrentSpace = nil }
        if let library, let symbol = dlsym(library, "SLSCopyWindowsWithOptionsAndTags") { copyWindows = unsafeBitCast(symbol, to: CopyWindows.self) } else { copyWindows = nil }
        observers.append(NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main) { [weak self] _ in
            // Read immediately, then retry on the next frames in case Dock has
            // posted before its managed-space dictionary is fully committed.
            self?.forceApplicationRefresh()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.016) { self?.refresh() }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { self?.forceApplicationRefresh() }
        })
        for name in [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification, NSWorkspace.didHideApplicationNotification, NSWorkspace.didUnhideApplicationNotification, NSWorkspace.didActivateApplicationNotification] {
            observers.append(NSWorkspace.shared.notificationCenter.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                self?.forceApplicationRefresh()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { self?.forceApplicationRefresh() }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { self?.forceApplicationRefresh() }
            })
        }
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now(), repeating: .milliseconds(50), leeway: .milliseconds(5))
        timer.setEventHandler { [weak self] in self?.refresh() }
        timer.resume(); refreshTimer = timer
        refresh()
    }

    deinit {
        observers.forEach(NSWorkspace.shared.notificationCenter.removeObserver)
        refreshTimer?.cancel()
        if let library { dlclose(library) }
    }

    func refresh() {
        guard let mainConnection, let copySpaces, let array = copySpaces(mainConnection())?.takeRetainedValue() as? [[String: Any]], !array.isEmpty else {
            canReadSpaces = false; return
        }
        let display = array.first(where: { ($0["Main"] as? Bool) == true }) ?? array[0]
        guard let spaces = display["Spaces"] as? [[String: Any]], let current = display["Current Space"] as? [String: Any], let currentID = number(current["ManagedSpaceID"]) else { canReadSpaces = false; return }
        let ordinary = spaces.filter { (number($0["type"]) ?? 0) == 0 }
        let ids = ordinary.compactMap { number($0["ManagedSpaceID"]) }
        let newCount = max(ids.count, 1)
        if desktopCount != newCount { desktopCount = newCount }
        if let index = ids.firstIndex(of: currentID), currentDesktop != index + 1 { currentDesktop = index + 1 }
        if Date().timeIntervalSince(lastApplicationRefresh) >= 0.15 {
            lastApplicationRefresh = Date(); refreshDesktopApplications(spaces: ordinary)
        }
        if !canReadSpaces { canReadSpaces = true }
    }

    private func forceApplicationRefresh() {
        lastApplicationRefresh = .distantPast
        refresh()
    }

    func icon(forDesktop number: Int) -> NSImage? {
        guard let app = desktopApplications[number] else { return nil }
        if let cached = iconCache.object(forKey: app.bundlePath as NSString) { return cached }
        let icon = NSWorkspace.shared.icon(forFile: app.bundlePath); icon.size = NSSize(width: 32, height: 32)
        iconCache.setObject(icon, forKey: app.bundlePath as NSString)
        return icon
    }

    private func refreshDesktopApplications(spaces: [[String: Any]]) {
        guard let mainConnection, let copyWindows else { return }
        var result: [Int: WorkspaceApplication] = [:]
        for (index, space) in spaces.enumerated() {
            guard let id = number(space["ManagedSpaceID"]) else { continue }
            var setTags: UInt64 = 0, clearTags: UInt64 = 0
            guard let values = copyWindows(mainConnection(), 0, [NSNumber(value: id)] as CFArray, 0x2, &setTags, &clearTags)?.takeRetainedValue() as? [NSNumber] else { continue }
            for value in values {
                let windowID = CGWindowID(value.uint32Value)
                guard let info = CGWindowListCopyWindowInfo([.optionIncludingWindow], windowID) as? [[String: Any]], let window = info.first,
                      (window[kCGWindowLayer as String] as? NSNumber)?.intValue == 0,
                      let ownerPID = (window[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value,
                      ownerPID != ProcessInfo.processInfo.processIdentifier,
                      let app = NSRunningApplication(processIdentifier: ownerPID), app.activationPolicy == .regular,
                      let bundleURL = app.bundleURL else { continue }
                result[index + 1] = WorkspaceApplication(name: app.localizedName ?? "Application", bundlePath: bundleURL.path)
                break
            }
        }
        if result != desktopApplications { desktopApplications = result }
    }

    func switchTo(_ number: Int, report: @escaping (String) -> Void) {
        guard number >= 1, number <= max(desktopCount, 1) else { return }
        let previous = currentDesktop
        if number == previous { return }
        currentDesktop = number
        if experimentalTransitionsEnabled {
            let animated = transitionController.perform(direction: number > previous ? 1 : -1) { [weak self] in self?.setDesktopDirectly(number) ?? false }
            if animated {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.26) { [weak self] in self?.refresh() }
                return
            }
        }
        WorkspaceController.switchTo(number)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
            self?.refresh()
            if self?.currentDesktop != number { report("Turn on Control–\(number) in System Settings › Keyboard › Keyboard Shortcuts › Mission Control") }
        }
    }

    private func setDesktopDirectly(_ number: Int) -> Bool {
        guard let mainConnection, let copySpaces, let setCurrentSpace,
              let displays = copySpaces(mainConnection())?.takeRetainedValue() as? [[String: Any]] else { return false }
        let connection = mainConnection()
        var changed = false
        for display in displays {
            guard let spaces = display["Spaces"] as? [[String: Any]],
                  let current = display["Current Space"] as? [String: Any] else { continue }
            let ordinary = spaces.filter { (self.number($0["type"]) ?? 0) == 0 }
            guard ordinary.indices.contains(number - 1), let target = self.number(ordinary[number - 1]["ManagedSpaceID"]) else { continue }
            let identifier = (current["Display Identifier"] as? String) ?? ordinary.compactMap { $0["Display Identifier"] as? String }.first ?? (display["Display Identifier"] as? String) ?? "Main"
            if setCurrentSpace(connection, identifier as CFString, UInt64(target)) == 0 { changed = true }
        }
        if changed { DispatchQueue.main.async { [weak self] in self?.refresh() } }
        return changed
    }

    /// Visits each ordinary Mission Control desktop directly through the same
    /// SkyLight managed-space data Ryft already reads. The original spaces
    /// are restored after updating, avoiding reliance on Control-number keys.
    func visitEveryDesktop(_ visit: @escaping (NSScreen) -> Void, completion: @escaping () -> Void) {
        guard let mainConnection, let copySpaces, let setCurrentSpace,
              let displays = copySpaces(mainConnection())?.takeRetainedValue() as? [[String: Any]] else { NSScreen.screens.forEach(visit); completion(); return }
        struct Target { let display: String; let space: UInt64; let screen: NSScreen }
        var targets: [Target] = []; var originals: [(String, UInt64)] = []
        for display in displays {
            guard let spaces = display["Spaces"] as? [[String: Any]],
                  let current = display["Current Space"] as? [String: Any],
                  let currentID = number(current["ManagedSpaceID"]) else { continue }
            let identifier = (current["Display Identifier"] as? String) ?? spaces.compactMap { $0["Display Identifier"] as? String }.first ?? (display["Display Identifier"] as? String) ?? "Main"
            guard let screen = screen(forDisplayIdentifier: identifier) else { continue }
            originals.append((identifier, UInt64(currentID)))
            for space in spaces where (number(space["type"]) ?? 0) == 0 {
                if let id = number(space["ManagedSpaceID"]) { targets.append(Target(display: identifier, space: UInt64(id), screen: screen)) }
            }
        }
        guard !targets.isEmpty else { NSScreen.screens.forEach(visit); completion(); return }
        let connection = mainConnection()
        func step(_ index: Int) {
            guard index < targets.count else {
                originals.forEach { _ = setCurrentSpace(connection, $0.0 as CFString, $0.1) }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { self.refresh(); completion() }
                return
            }
            let target = targets[index]; _ = setCurrentSpace(connection, target.display as CFString, target.space)
            // SkyLight switches immediately, but NSWorkspace needs a moment to bind
            // desktopImageURL to the newly active managed Space.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.42) {
                visit(target.screen)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { step(index + 1) }
            }
        }
        step(0)
    }

    private func screen(forDisplayIdentifier identifier: String) -> NSScreen? {
        if identifier == "Main" { return NSScreen.main }
        return NSScreen.screens.first { screen in
            guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber,
                  let uuid = CGDisplayCreateUUIDFromDisplayID(CGDirectDisplayID(number.uint32Value))?.takeRetainedValue() else { return false }
            return CFUUIDCreateString(nil, uuid) as String == identifier
        }
    }

    private func number(_ value: Any?) -> Int? {
        if let value = value as? NSNumber { return value.intValue }
        if let value = value as? Int { return value }
        return nil
    }
}
