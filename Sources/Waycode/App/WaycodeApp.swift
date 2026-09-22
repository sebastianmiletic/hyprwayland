import SwiftUI
import Combine

@main
struct WaycodeApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @ObservedObject private var model = AppModel.shared

    var body: some Scene {
        WindowGroup("Waycode") { SettingsView(model: model) }
            .defaultSize(width: 1050, height: 720)
            .commands {
                CommandGroup(after: .appInfo) {
                    Button("Toggle Wallpaper Gallery") { appDelegate.showWallpaperGallery() }
                    Button("Toggle Desktop Bar") { model.configuration.bar.enabled.toggle() }.keyboardShortcut("b", modifiers: [.option])
                }
                CommandGroup(replacing: .newItem) { }
            }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var barController: BarPanelController?
    private var wallpaperController: WallpaperWindowController?
    private var sidePanelController: SidePanelController?
    private var hotkeys: GlobalHotkeyManager?
    private var cancellable: AnyCancellable?
    private var observers: [NSObjectProtocol] = []
    private var statusItem: NSStatusItem?
    private var settingsWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        let model = AppModel.shared
        _ = model.notifications
        barController = BarPanelController(model: model)
        wallpaperController = WallpaperWindowController(model: model)
        sidePanelController = SidePanelController(model: model)
        let manager = GlobalHotkeyManager()
        manager.onShortcut = { [weak self] shortcut in self?.perform(shortcut) }
        manager.onWorkspace = { number in model.workspaces.switchTo(number) { model.statusMessage = $0 } }
        manager.register(model.configuration.shortcuts)
        hotkeys = manager
        cancellable = model.$configuration.map(\.shortcuts).removeDuplicates().sink { [weak manager] in manager?.register($0) }
        observers.append(NotificationCenter.default.addObserver(forName: .waycodeShowWallpapers, object: nil, queue: .main) { [weak self] _ in self?.showWallpaperGallery() })
        observers.append(NotificationCenter.default.addObserver(forName: .waycodeShowSettings, object: nil, queue: .main) { [weak self] _ in self?.showSettings() })
        observers.append(NotificationCenter.default.addObserver(forName: .waycodeToggleLeftSidebar, object: nil, queue: .main) { [weak self] _ in self?.sidePanelController?.toggleLeft() })
        observers.append(NotificationCenter.default.addObserver(forName: .waycodeToggleRightSidebar, object: nil, queue: .main) { [weak self] note in self?.sidePanelController?.toggleRight(detail: note.object as? String ?? "") })
        installStatusItem()
        DispatchQueue.main.async { [weak self] in self?.captureSettingsWindow() }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func applicationWillResignActive(_ notification: Notification) { AppModel.shared.save() }
    func applicationWillTerminate(_ notification: Notification) { AppModel.shared.save() }
    func showWallpaperGallery() { wallpaperController?.show() }
    func showSettings() {
        captureSettingsWindow()
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
        settingsWindow?.orderFrontRegardless()
    }

    private func captureSettingsWindow() {
        if settingsWindow == nil {
            settingsWindow = NSApp.windows.first(where: { !($0 is NSPanel) && $0.title != "Wallpaper gallery" }) ?? NSApp.windows.first(where: { $0.title == "Waycode" })
        }
        guard let settingsWindow else { return }
        settingsWindow.isReleasedWhenClosed = false
        settingsWindow.level = .floating
        settingsWindow.hidesOnDeactivate = false
        settingsWindow.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
    }

    private func installStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = item.button {
            button.image = NSImage(systemSymbolName: "rectangle.split.2x1.fill", accessibilityDescription: "Waycode")
            button.image?.isTemplate = true
            button.toolTip = "Waycode"
        }
        let menu = NSMenu()
        menu.addItem(menuItem("Open Waycode Settings", action: #selector(openSettingsFromMenu)))
        menu.addItem(menuItem("Wallpaper Gallery", action: #selector(openWallpapersFromMenu)))
        menu.addItem(menuItem("Random Wallpaper", action: #selector(randomWallpaperFromMenu)))
        menu.addItem(.separator())
        menu.addItem(menuItem("Open Tools Sidebar", action: #selector(leftSidebarFromMenu)))
        menu.addItem(menuItem("Open Control Center", action: #selector(rightSidebarFromMenu)))
        menu.addItem(menuItem("Toggle Desktop Bar", action: #selector(toggleBarFromMenu)))
        menu.addItem(.separator())
        menu.addItem(menuItem("Quit Waycode", action: #selector(quitFromMenu)))
        item.menu = menu
        statusItem = item
    }

    private func menuItem(_ title: String, action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: ""); item.target = self; return item
    }
    @objc private func openSettingsFromMenu() { showSettings() }
    @objc private func openWallpapersFromMenu() { showWallpaperGallery() }
    @objc private func randomWallpaperFromMenu() { AppModel.shared.randomWallpaper() }
    @objc private func leftSidebarFromMenu() { sidePanelController?.toggleLeft() }
    @objc private func rightSidebarFromMenu() { sidePanelController?.toggleRight() }
    @objc private func toggleBarFromMenu() { AppModel.shared.configuration.bar.enabled.toggle() }
    @objc private func quitFromMenu() { NSApp.terminate(nil) }

    func perform(_ shortcut: ShortcutConfiguration) {
        let model = AppModel.shared
        switch shortcut.action {
        case .wallpaper: showWallpaperGallery()
        case .toggleBar: model.configuration.bar.enabled.toggle()
        case .settings: showSettings()
        case .randomWallpaper: model.randomWallpaper()
        case .tileWindows: model.tiling.tileNow()
        case .focusNextWindow: model.tiling.focusNext()
        case .toggleTiling:
            model.configuration.tiling.enabled.toggle()
            model.configuration.tiling.autoTile = model.configuration.tiling.enabled
        case .openFinder:
            NSWorkspace.shared.openApplication(at: URL(fileURLWithPath: "/System/Library/CoreServices/Finder.app"), configuration: .init())
        case .openApplication:
            if let path = shortcut.target, !path.isEmpty { NSWorkspace.shared.open(URL(fileURLWithPath: path)) }
        case .runCommand:
            guard let command = shortcut.target, !command.isEmpty else { return }
            let process = Process(); process.executableURL = URL(fileURLWithPath: "/bin/zsh"); process.arguments = ["-lc", command]
            try? process.run()
        case .leftSidebar: sidePanelController?.toggleLeft()
        case .rightSidebar: sidePanelController?.toggleRight()
        case .quitFrontmost:
            guard let app = NSWorkspace.shared.frontmostApplication else { return }
            if app.processIdentifier == ProcessInfo.processInfo.processIdentifier { NSApp.terminate(nil) }
            else { _ = app.terminate() }
        }
    }
}
