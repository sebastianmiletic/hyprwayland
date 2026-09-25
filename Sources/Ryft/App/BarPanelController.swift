import AppKit
import SwiftUI
import Combine

/// Keeps one long-lived panel per display. Visual edits flow through SwiftUI and
/// never destroy the native window, so dragging opacity, blur, color, or spacing
/// controls cannot make the bar flash, jump, or temporarily change screens.
final class BarPanelController {
    private final class PanelContext: ObservableObject {
        let interactionID = UUID()
        @Published var notchWidth: Double
        @Published var topReservedHeight: Double
        @Published var screenSize: CGSize
        @Published var wallpaperPath: String
        init(notchWidth: Double, topReservedHeight: Double, screenSize: CGSize, wallpaperPath: String) {
            self.notchWidth = notchWidth
            self.topReservedHeight = topReservedHeight
            self.screenSize = screenSize
            self.wallpaperPath = wallpaperPath
        }
    }
    private struct PanelEntry {
        let screenID: NSNumber
        let panel: NSPanel
        let context: PanelContext
        let cornerPanels: [NSPanel]
        let menuBarCoverPanel: NSPanel
    }

    private let model: AppModel
    private let spaceCoverManager = SpaceMenuBarCoverManager()
    private var entries: [PanelEntry] = []
    private var cancellables = Set<AnyCancellable>()
    private var coversWaitingForWallpaper = Set<ObjectIdentifier>()
    private var coverWallpaperBeforeSpaceChange: [NSNumber: String] = [:]
    private var spaceChangeGeneration = UUID()

    init(model: AppModel) {
        self.model = model
        model.$configuration.map(\.bar).sink { [weak self] config in self?.synchronize(config) }.store(in: &cancellables)
        NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)
            .sink { [weak self] _ in self?.synchronize(self?.model.configuration.bar) }.store(in: &cancellables)
        NotificationCenter.default.publisher(for: .ryftWallpaperChanged)
            .sink { [weak self] _ in self?.synchronize(self?.model.configuration.bar) }.store(in: &cancellables)
        NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.activeSpaceDidChangeNotification)
            .sink { [weak self] _ in
                guard let self else { return }
                self.spaceCoverManager.synchronize(config: self.model.configuration.bar, screens: NSScreen.screens)
            }.store(in: &cancellables)
        Timer.publish(every: 1, on: .main, in: .common).autoconnect()
            .sink { [weak self] _ in self?.refreshWallpaperPaths() }.store(in: &cancellables)
        synchronize(model.configuration.bar)
    }

    private func synchronize(_ optionalConfig: BarConfiguration?) {
        guard let config = optionalConfig else { return }
        guard config.enabled else {
            entries.forEach { $0.panel.orderOut(nil); $0.cornerPanels.forEach { $0.orderOut(nil) }; $0.menuBarCoverPanel.orderOut(nil) }
            entries.removeAll()
            return
        }

        let desiredScreens = config.showOnAllDisplays ? NSScreen.screens : [NSScreen.main].compactMap { $0 }
        spaceCoverManager.synchronize(config: config, screens: desiredScreens)
        let desiredIDs = Set(desiredScreens.compactMap(screenID))

        for entry in entries where !desiredIDs.contains(entry.screenID) { entry.panel.orderOut(nil); entry.cornerPanels.forEach { $0.orderOut(nil) }; entry.menuBarCoverPanel.orderOut(nil) }
        entries.removeAll { !desiredIDs.contains($0.screenID) }

        for screen in desiredScreens {
            guard let id = screenID(screen) else { continue }
            if let index = entries.firstIndex(where: { $0.screenID == id }) {
                update(entries[index], on: screen, config: config)
            } else {
                let entry = makeEntry(on: screen, id: id, config: config)
                entries.append(entry)
                entry.panel.orderFrontRegardless()
                updateCornerPanels(entry.cornerPanels, on: screen, config: config)
                updateMenuBarCover(entry.menuBarCoverPanel, on: screen, config: config)
            }
        }
    }

    private func makeEntry(on screen: NSScreen, id: NSNumber, config: BarConfiguration) -> PanelEntry {
        let context = PanelContext(
            notchWidth: notchWidth(for: screen, config: config),
            topReservedHeight: topReservedHeight(for: screen, config: config),
            screenSize: screen.frame.size,
            wallpaperPath: wallpaperPath(for: screen)
        )
        let panel = InteractiveBarPanel(contentRect: panelFrame(on: screen, config: config), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 3)
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.alphaValue = 1
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        // Experimental Hyprland-style Space behavior: keep the shell surface
        // fixed while macOS moves desktop windows beneath it. This is isolated
        // to the bar panel so it can be reverted without touching Space logic.
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        panel.isMovable = false
        panel.ignoresMouseEvents = false
        panel.contentView = NSHostingView(rootView: StableBarRoot(model: model, context: context))
        let corners = [makeCornerPanel(isLeft: true), makeCornerPanel(isLeft: false)]
        let menuBarCover = makeMenuBarCoverPanel(context: context)
        return PanelEntry(screenID: id, panel: panel, context: context, cornerPanels: corners, menuBarCoverPanel: menuBarCover)
    }

    private func update(_ entry: PanelEntry, on screen: NSScreen, config: BarConfiguration) {
        entry.panel.alphaValue = 1
        let newNotch = notchWidth(for: screen, config: config)
        let newReservedHeight = topReservedHeight(for: screen, config: config)
        if entry.context.notchWidth != newNotch { entry.context.notchWidth = newNotch }
        if entry.context.topReservedHeight != newReservedHeight { entry.context.topReservedHeight = newReservedHeight }
        if entry.context.screenSize != screen.frame.size { entry.context.screenSize = screen.frame.size }
        let newWallpaperPath = wallpaperPath(for: screen)
        if entry.context.wallpaperPath != newWallpaperPath { entry.context.wallpaperPath = newWallpaperPath }
        let frame = panelFrame(on: screen, config: config)
        if !entry.panel.frame.equalTo(frame) { entry.panel.setFrame(frame, display: true, animate: false) }
        if !entry.panel.isVisible { entry.panel.orderFrontRegardless() }
        updateCornerPanels(entry.cornerPanels, on: screen, config: config)
        updateMenuBarCover(entry.menuBarCoverPanel, on: screen, config: config)
    }

    private func makeMenuBarCoverPanel(context: PanelContext) -> NSPanel {
        let panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        // Native status items can share mainMenu + 1. Keep the wallpaper crop
        // above every Apple menu-bar surface, while Ryft remains one level higher.
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 2)
        // Stay fully opaque even while a large wallpaper is being decoded.
        // Black is only a failure fallback; WallpaperCropView paints the exact
        // per-Space crop over it as soon as the image is available.
        panel.backgroundColor = .black; panel.isOpaque = true; panel.hasShadow = false; panel.hidesOnDeactivate = false; panel.ignoresMouseEvents = true
        // Belong to the current Space rather than remaining stationary across
        // every Space. During a swipe, each cover therefore travels with the
        // wallpaper it was cropped from instead of bleeding into the next one.
        panel.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary, .ignoresCycle]
        panel.contentView = NSHostingView(rootView: MenuBarCoverRoot(context: context))
        return panel
    }

    private func updateMenuBarCover(_ panel: NSPanel, on screen: NSScreen, config: BarConfiguration) {
        // Per-Space covers are owned by SpaceMenuBarCoverManager. Retain this
        // legacy panel only to avoid rebuilding long-lived bar entries.
        panel.orderOut(nil)
    }

    private func prepareCoversForSpaceChange() {
        let generation = UUID()
        spaceChangeGeneration = generation
        coverWallpaperBeforeSpaceChange = Dictionary(uniqueKeysWithValues: entries.map { ($0.screenID, $0.context.wallpaperPath) })
        coversWaitingForWallpaper = Set(entries.map { ObjectIdentifier($0.menuBarCoverPanel) })
        // Never remove the cover between Spaces. Keeping it opaque prevents a
        // one-frame flash of Apple's menu bar while wallpaper metadata catches up.
        // orderFrontRegardless is intentional even when AppKit reports the
        // panel as visible: a visible moveToActiveSpace panel may still belong
        // to the outgoing Space until it is explicitly ordered on the new one.
        entries.forEach { $0.menuBarCoverPanel.orderFrontRegardless() }
        // Poll on the first transition frames instead of waiting for coarse
        // retries. NSWorkspace usually exposes the destination wallpaper within
        // one or two frames; later attempts cover slower Mission Control paths.
        let delays = [0.0, 0.016, 0.033, 0.066, 0.12, 0.20, 0.32, 0.50]
        for (attempt, delay) in delays.enumerated() {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                self?.restoreCoversAfterSpaceChange(generation: generation, force: attempt == delays.count - 1)
            }
        }
    }

    private func restoreCoversAfterSpaceChange(generation: UUID, force: Bool) {
        guard generation == spaceChangeGeneration else { return }
        let config = model.configuration.bar
        for entry in entries {
            guard let screen = NSScreen.screens.first(where: { screenID($0) == entry.screenID }) else { continue }
            let path = wallpaperPath(for: screen)
            let previous = coverWallpaperBeforeSpaceChange[entry.screenID] ?? ""
            guard force || path != previous else { continue }
            if entry.context.wallpaperPath != path { entry.context.wallpaperPath = path }
            coversWaitingForWallpaper.remove(ObjectIdentifier(entry.menuBarCoverPanel))
            updateMenuBarCover(entry.menuBarCoverPanel, on: screen, config: config)
        }
        if coversWaitingForWallpaper.isEmpty || force {
            if force { coversWaitingForWallpaper.removeAll() }
            coverWallpaperBeforeSpaceChange.removeAll()
        }
    }

    private func makeCornerPanel(isLeft: Bool) -> NSPanel {
        let panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 3)
        panel.backgroundColor = .clear; panel.isOpaque = false; panel.hasShadow = false; panel.hidesOnDeactivate = false; panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        panel.contentView = NSHostingView(rootView: DisplayCornerMask(isLeft: isLeft))
        return panel
    }

    private func updateCornerPanels(_ panels: [NSPanel], on screen: NSScreen, config: BarConfiguration) {
        guard config.roundBottomDisplayCorners, config.displayCornerRadius > 0 else { panels.forEach { $0.orderOut(nil) }; return }
        let radius = config.displayCornerRadius
        let frames = [
            NSRect(x: screen.frame.minX, y: screen.frame.minY, width: radius, height: radius),
            NSRect(x: screen.frame.maxX - radius, y: screen.frame.minY, width: radius, height: radius)
        ]
        for (panel, frame) in zip(panels, frames) { panel.setFrame(frame, display: true); panel.alphaValue = 1; panel.orderFrontRegardless() }
    }

    private func panelFrame(on screen: NSScreen, config: BarConfiguration) -> NSRect {
        let edgeInsets = config.presentation == .top ? 0 : config.outerInset * 2
        let thickness = config.height + edgeInsets + (config.position == .top ? topReservedHeight(for: screen, config: config) : 0)
        switch config.position {
        case .top: return NSRect(x: screen.frame.minX, y: screen.frame.maxY - thickness, width: screen.frame.width, height: thickness)
        case .bottom: return NSRect(x: screen.frame.minX, y: screen.frame.minY, width: screen.frame.width, height: thickness)
        case .left: return NSRect(x: screen.frame.minX, y: screen.frame.minY, width: thickness, height: screen.frame.height)
        case .right: return NSRect(x: screen.frame.maxX - thickness, y: screen.frame.minY, width: thickness, height: screen.frame.height)
        }
    }

    private func notchWidth(for screen: NSScreen, config: BarConfiguration) -> Double {
        guard config.position == .top, (config.reserveNotchSpace || config.splitAroundNotch), !config.notchMaskEnabled else { return 0 }
        if config.manualNotchWidth > 0 { return config.manualNotchWidth }
        guard let left = screen.auxiliaryTopLeftArea, let right = screen.auxiliaryTopRightArea else { return 0 }
        return max(0, right.minX - left.maxX)
    }

    private func topReservedHeight(for screen: NSScreen, config: BarConfiguration) -> Double {
        guard config.position == .top, config.notchMaskEnabled else { return 0 }
        if config.notchMaskHeight > 0 { return config.notchMaskHeight }
        guard screen.auxiliaryTopLeftArea != nil || screen.auxiliaryTopRightArea != nil else { return 0 }
        return max(screen.safeAreaInsets.top, 32)
    }

    private func wallpaperPath(for screen: NSScreen) -> String {
        NSWorkspace.shared.desktopImageURL(for: screen)?.path ?? model.configuration.currentWallpaper
    }

    private func refreshWallpaperPaths() {
        for entry in entries {
            guard !coversWaitingForWallpaper.contains(ObjectIdentifier(entry.menuBarCoverPanel)),
                  let screen = NSScreen.screens.first(where: { screenID($0) == entry.screenID }) else { continue }
            let path = wallpaperPath(for: screen)
            if entry.context.wallpaperPath != path { entry.context.wallpaperPath = path }
        }
    }

    private func screenID(_ screen: NSScreen) -> NSNumber? { screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber }

    private struct DisplayCornerMask: View {
        let isLeft: Bool
        var body: some View {
            GeometryReader { proxy in
                Path { path in
                    let r = proxy.size.width
                    path.move(to: CGPoint(x: 0, y: 0)); path.addLine(to: CGPoint(x: 0, y: r)); path.addLine(to: CGPoint(x: r, y: r))
                    path.addCurve(to: CGPoint(x: 0, y: 0), control1: CGPoint(x: r * 0.448, y: r), control2: CGPoint(x: 0, y: r * 0.448)); path.closeSubpath()
                }.fill(Color(red: 0, green: 0, blue: 0)).scaleEffect(x: isLeft ? 1 : -1, y: 1)
            }
        }
    }

    private struct MenuBarCoverRoot: View {
        @ObservedObject var context: PanelContext
        var body: some View { WallpaperMenuBarCover(path: context.wallpaperPath, screenSize: context.screenSize) }
    }

    private struct StableBarRoot: View {
        @ObservedObject var model: AppModel
        @ObservedObject var context: PanelContext
        var body: some View {
            BarView(model: model, notchWidth: context.notchWidth, topReservedHeight: context.topReservedHeight, interactionID: context.interactionID)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

private struct WallpaperMenuBarCover: NSViewRepresentable {
    let path: String
    let screenSize: CGSize
    func makeNSView(context: Context) -> WallpaperCropView { WallpaperCropView() }
    func updateNSView(_ view: WallpaperCropView, context: Context) {
        if view.path != path {
            view.path = path
            view.image = NSImage(contentsOfFile: path)
        }
        if view.screenSize != screenSize { view.screenSize = screenSize }
        view.needsDisplay = true
    }
}

private final class WallpaperCropView: NSView {
    var path = ""
    var image: NSImage?
    var screenSize: CGSize = .zero
    override var isOpaque: Bool { image != nil }
    override func draw(_ dirtyRect: NSRect) {
        guard let image, screenSize.width > 0, screenSize.height > 0, image.size.width > 0, image.size.height > 0 else { return }
        let scale = max(screenSize.width / image.size.width, screenSize.height / image.size.height)
        let drawn = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let destination = CGRect(
            x: (screenSize.width - drawn.width) / 2,
            y: bounds.height - (screenSize.height + drawn.height) / 2,
            width: drawn.width,
            height: drawn.height
        )
        image.draw(in: destination, from: .zero, operation: .copy, fraction: 1, respectFlipped: true, hints: [.interpolation: NSImageInterpolation.high])
    }
}

private final class SpaceMenuBarCoverManager {
    private struct SpaceInfo { let id: UInt64; let uuid: String; let display: String }
    private struct Key: Hashable { let space: UInt64; let display: String }
    private struct Cover { let panel: NSPanel; let view: WallpaperCropView }
    private typealias MainConnection = @convention(c) () -> UInt32
    private typealias CopySpaces = @convention(c) (UInt32) -> Unmanaged<CFArray>?
    private typealias AddWindows = @convention(c) (UInt32, CFArray, CFArray) -> Void

    private let library: UnsafeMutableRawPointer?
    private let mainConnection: MainConnection?
    private let copySpaces: CopySpaces?
    private let addWindows: AddWindows?
    private var covers: [Key: Cover] = [:]

    init() {
        library = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_LAZY)
        if let library, let symbol = dlsym(library, "CGSMainConnectionID") { mainConnection = unsafeBitCast(symbol, to: MainConnection.self) } else { mainConnection = nil }
        if let library, let symbol = dlsym(library, "CGSCopyManagedDisplaySpaces") { copySpaces = unsafeBitCast(symbol, to: CopySpaces.self) } else { copySpaces = nil }
        if let library, let symbol = dlsym(library, "SLSAddWindowsToSpaces") { addWindows = unsafeBitCast(symbol, to: AddWindows.self) } else { addWindows = nil }
    }

    deinit {
        covers.values.forEach { $0.panel.orderOut(nil) }
        if let library { dlclose(library) }
    }

    func synchronize(config: BarConfiguration, screens: [NSScreen]) {
        guard config.enabled, let mainConnection, let copySpaces, let addWindows,
              let displays = copySpaces(mainConnection())?.takeRetainedValue() as? [[String: Any]] else {
            covers.values.forEach { $0.panel.orderOut(nil) }
            return
        }
        let screenByDisplay = Dictionary(uniqueKeysWithValues: screens.compactMap { screen -> (String, NSScreen)? in
            guard let identifier = displayIdentifier(for: screen) else { return nil }
            return (identifier, screen)
        })
        var desired = Set<Key>()
        let connection = mainConnection()
        for display in displays {
            let fallbackDisplay = display["Display Identifier"] as? String
            guard let spaces = display["Spaces"] as? [[String: Any]] else { continue }
            for value in spaces where (value["type"] as? NSNumber)?.intValue == 0 {
                guard let id = (value["ManagedSpaceID"] as? NSNumber)?.uint64Value,
                      let uuid = value["uuid"] as? String,
                      let displayID = (value["Display Identifier"] as? String) ?? fallbackDisplay,
                      let screen = screenByDisplay[displayID] else { continue }
                let info = SpaceInfo(id: id, uuid: uuid, display: displayID)
                let key = Key(space: id, display: displayID)
                desired.insert(key)
                let path = wallpaperPath(space: info.uuid, display: displayID)
                    ?? NSWorkspace.shared.desktopImageURL(for: screen)?.path
                    ?? ""
                if let cover = covers[key] { update(cover, screen: screen, path: path) }
                else {
                    let cover = makeCover(screen: screen, path: path)
                    covers[key] = cover
                    cover.panel.orderFrontRegardless()
                    addWindows(connection, [NSNumber(value: cover.panel.windowNumber)] as CFArray, [NSNumber(value: id)] as CFArray)
                }
            }
        }
        let stale = covers.keys.filter { !desired.contains($0) }
        for key in stale { covers[key]?.panel.orderOut(nil); covers.removeValue(forKey: key) }
    }

    private func makeCover(screen: NSScreen, path: String) -> Cover {
        let height = ceil(DisplayLayoutMetrics.menuBarHeight(for: screen)) + 1
        let frame = NSRect(x: screen.frame.minX, y: screen.frame.maxY - height, width: screen.frame.width, height: height)
        let panel = NSPanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 2)
        panel.backgroundColor = .black; panel.isOpaque = true; panel.hasShadow = false
        panel.hidesOnDeactivate = false; panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.fullScreenAuxiliary, .ignoresCycle]
        let view = WallpaperCropView(frame: NSRect(origin: .zero, size: frame.size))
        panel.contentView = view
        let cover = Cover(panel: panel, view: view)
        update(cover, screen: screen, path: path)
        return cover
    }

    private func update(_ cover: Cover, screen: NSScreen, path: String) {
        let height = ceil(DisplayLayoutMetrics.menuBarHeight(for: screen)) + 1
        let frame = NSRect(x: screen.frame.minX, y: screen.frame.maxY - height, width: screen.frame.width, height: height)
        if !cover.panel.frame.equalTo(frame) { cover.panel.setFrame(frame, display: true) }
        cover.view.screenSize = screen.frame.size
        if cover.view.path != path {
            cover.view.path = path
            cover.view.image = NSImage(contentsOfFile: path)
        }
        cover.view.needsDisplay = true
    }

    private func wallpaperPath(space: String, display: String) -> String? {
        let url = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/com.apple.wallpaper/Store/Index.plist")
        guard let data = try? Data(contentsOf: url),
              let root = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              let spaces = root["Spaces"] as? [String: Any],
              let value = spaces[space] as? [String: Any] else { return nil }
        let displayValue = ((value["Displays"] as? [String: Any])?[display] as? [String: Any]) ?? (value["Default"] as? [String: Any])
        guard let desktop = displayValue?["Desktop"] as? [String: Any],
              let content = desktop["Content"] as? [String: Any],
              let choices = content["Choices"] as? [[String: Any]],
              let configuration = choices.first?["Configuration"] as? Data,
              let decoded = try? PropertyListSerialization.propertyList(from: configuration, format: nil) else { return nil }
        return findFileURL(in: decoded)?.path
    }

    private func findFileURL(in value: Any) -> URL? {
        if let dictionary = value as? [String: Any] {
            if let relative = (dictionary["url"] as? [String: Any])?["relative"] as? String,
               let url = URL(string: relative), url.isFileURL { return url }
            for child in dictionary.values { if let result = findFileURL(in: child) { return result } }
        } else if let array = value as? [Any] {
            for child in array { if let result = findFileURL(in: child) { return result } }
        }
        return nil
    }

    private func displayIdentifier(for screen: NSScreen) -> String? {
        guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber,
              let uuid = CGDisplayCreateUUIDFromDisplayID(CGDirectDisplayID(number.uint32Value))?.takeRetainedValue() else { return nil }
        return CFUUIDCreateString(nil, uuid) as String
    }
}

private final class InteractiveBarPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}
