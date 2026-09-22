import SwiftUI
import Combine
import QuartzCore

@main
struct RyftApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @ObservedObject private var model = AppModel.shared

    var body: some Scene {
        WindowGroup("Ryft") { SettingsView(model: model) }
            .defaultSize(width: 1050, height: 720)
            .commands {
                CommandGroup(after: .appInfo) {
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
    private var settingsAnimationInProgress = false

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
        cancellable = model.$configuration.map(\.shortcuts).removeDuplicates().dropFirst().sink { [weak manager] in manager?.register($0) }
        observers.append(NotificationCenter.default.addObserver(forName: .ryftShowWallpapers, object: nil, queue: .main) { [weak self] _ in self?.showWallpaperGallery() })
        observers.append(NotificationCenter.default.addObserver(forName: .ryftShowSettings, object: nil, queue: .main) { [weak self] _ in self?.showSettings() })
        observers.append(NotificationCenter.default.addObserver(forName: .ryftToggleLeftSidebar, object: nil, queue: .main) { [weak self] _ in self?.sidePanelController?.toggleLeft() })
        observers.append(NotificationCenter.default.addObserver(forName: .ryftToggleRightSidebar, object: nil, queue: .main) { [weak self] note in self?.sidePanelController?.toggleRight(detail: note.object as? String ?? "") })
        observers.append(NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { _ in NSMenu.setMenuBarVisible(false) })
        installStatusItem()
        NSMenu.setMenuBarVisible(false)
        DispatchQueue.main.async { [weak self] in self?.captureSettingsWindow() }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func applicationWillResignActive(_ notification: Notification) { AppModel.shared.save() }
    func applicationWillTerminate(_ notification: Notification) { NSMenu.setMenuBarVisible(true); AppModel.shared.save() }
    func showWallpaperGallery() { wallpaperController?.show() }
    func showSettings() {
        captureSettingsWindow()
        guard let settingsWindow, !settingsAnimationInProgress else { return }
        if settingsWindow.isVisible { hideSettings(); return }
        AppModel.shared.selectedSection = .home
        NSApp.activate(ignoringOtherApps: true)
        let targetFrame = settingsWindow.frame
        if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            settingsWindow.alphaValue = 1; settingsWindow.makeKeyAndOrderFront(nil); settingsWindow.orderFrontRegardless()
            return
        }
        settingsAnimationInProgress = true
        settingsWindow.alphaValue = 0
        settingsWindow.setFrame(targetFrame.offsetBy(dx: 0, dy: -8), display: false)
        settingsWindow.makeKeyAndOrderFront(nil); settingsWindow.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.22
            context.timingFunction = CAMediaTimingFunction(controlPoints: 0.22, 1, 0.36, 1)
            settingsWindow.animator().alphaValue = 1
            settingsWindow.animator().setFrame(targetFrame, display: true)
        } completionHandler: { [weak self] in self?.settingsAnimationInProgress = false }
    }

    private func captureSettingsWindow() {
        if settingsWindow == nil {
            settingsWindow = NSApp.windows.first(where: { !($0 is NSPanel) && $0.title != "Wallpaper gallery" }) ?? NSApp.windows.first(where: { $0.title == "Ryft" })
        }
        guard let settingsWindow else { return }
        settingsWindow.isReleasedWhenClosed = false
        settingsWindow.level = .floating
        settingsWindow.hidesOnDeactivate = false
        settingsWindow.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        settingsWindow.standardWindowButton(.closeButton)?.target = self
        settingsWindow.standardWindowButton(.closeButton)?.action = #selector(closeSettingsWindow)
    }

    @objc private func closeSettingsWindow() { hideSettings() }
    private func hideSettings() {
        guard let settingsWindow, settingsWindow.isVisible, !settingsAnimationInProgress else { return }
        guard !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else { settingsWindow.orderOut(nil); return }
        settingsAnimationInProgress = true
        let targetFrame = settingsWindow.frame
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.16
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            settingsWindow.animator().alphaValue = 0
            settingsWindow.animator().setFrame(targetFrame.offsetBy(dx: 0, dy: -6), display: true)
        } completionHandler: { [weak self, weak settingsWindow] in
            settingsWindow?.orderOut(nil); settingsWindow?.alphaValue = 1
            settingsWindow?.setFrame(targetFrame, display: false)
            self?.settingsAnimationInProgress = false
        }
    }

    private func installStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = item.button {
            button.image = NSImage(systemSymbolName: "rectangle.split.2x1.fill", accessibilityDescription: "Ryft")
            button.image?.isTemplate = true
            button.toolTip = "Ryft"
        }
        let menu = NSMenu()
        menu.addItem(menuItem("Open Ryft Settings", action: #selector(openSettingsFromMenu)))
        menu.addItem(menuItem("Open Tools Sidebar", action: #selector(leftSidebarFromMenu)))
        menu.addItem(menuItem("Open Control Center", action: #selector(rightSidebarFromMenu)))
        menu.addItem(menuItem("Toggle Desktop Bar", action: #selector(toggleBarFromMenu)))
        menu.addItem(menuItem("Enable System-wide Shortcuts…", action: #selector(openInputMonitoringFromMenu)))
        menu.addItem(.separator())
        menu.addItem(menuItem("Quit Ryft", action: #selector(quitFromMenu)))
        item.menu = menu
        statusItem = item
    }

    private func menuItem(_ title: String, action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: ""); item.target = self; return item
    }
    @objc private func openSettingsFromMenu() { showSettings() }
    @objc private func leftSidebarFromMenu() { sidePanelController?.toggleLeft() }
    @objc private func rightSidebarFromMenu() { sidePanelController?.toggleRight() }
    @objc private func toggleBarFromMenu() { AppModel.shared.configuration.bar.enabled.toggle() }
    @objc private func openInputMonitoringFromMenu() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent") { NSWorkspace.shared.open(url) }
    }
    @objc private func quitFromMenu() { NSApp.terminate(nil) }

    func perform(_ shortcut: ShortcutConfiguration) {
        let model = AppModel.shared
        switch shortcut.action {
        case .wallpaper: showWallpaperGallery()
        case .toggleBar: model.configuration.bar.enabled.toggle()
        case .settings: showSettings()
        case .randomWallpaper: model.randomWallpaper()
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
