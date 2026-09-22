import AppKit
import Combine
import Darwin

/// Tracks the actual current Mission Control desktop. macOS exposes the change
/// notification publicly but not the desktop index, so Waycode reads the same
/// ordered Space metadata used by Dock through dynamically resolved SkyLight
/// symbols. It falls back to tracked keyboard navigation if Apple changes it.
final class WorkspaceService: ObservableObject {
    @Published private(set) var currentDesktop = 1
    @Published private(set) var desktopCount = 1
    @Published private(set) var canReadSpaces = false

    private typealias MainConnection = @convention(c) () -> UInt32
    private typealias CopySpaces = @convention(c) (UInt32) -> Unmanaged<CFArray>?
    private let library: UnsafeMutableRawPointer?
    private let mainConnection: MainConnection?
    private let copySpaces: CopySpaces?
    private var observer: NSObjectProtocol?
    private var refreshTimer: DispatchSourceTimer?

    init() {
        library = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_LAZY)
        if let library, let symbol = dlsym(library, "CGSMainConnectionID") { mainConnection = unsafeBitCast(symbol, to: MainConnection.self) } else { mainConnection = nil }
        if let library, let symbol = dlsym(library, "CGSCopyManagedDisplaySpaces") { copySpaces = unsafeBitCast(symbol, to: CopySpaces.self) } else { copySpaces = nil }
        observer = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main) { [weak self] _ in
            // Read immediately, then retry on the next frames in case Dock has
            // posted before its managed-space dictionary is fully committed.
            self?.refresh()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.016) { self?.refresh() }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { self?.refresh() }
        }
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now(), repeating: .milliseconds(50), leeway: .milliseconds(5))
        timer.setEventHandler { [weak self] in self?.refresh() }
        timer.resume(); refreshTimer = timer
        refresh()
    }

    deinit {
        if let observer { NSWorkspace.shared.notificationCenter.removeObserver(observer) }
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
        if !canReadSpaces { canReadSpaces = true }
    }

    func switchTo(_ number: Int, report: @escaping (String) -> Void) {
        guard number >= 1, number <= max(desktopCount, 1) else { return }
        if number == currentDesktop { return }
        currentDesktop = number
        WorkspaceController.switchTo(number)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
            self?.refresh()
            if self?.currentDesktop != number { report("Turn on Control–\(number) in System Settings › Keyboard › Keyboard Shortcuts › Mission Control") }
        }
    }

    private func number(_ value: Any?) -> Int? {
        if let value = value as? NSNumber { return value.intValue }
        if let value = value as? Int { return value }
        return nil
    }
}
