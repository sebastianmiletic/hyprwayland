import AppKit
import SwiftUI

final class WallpaperWindowController {
    private var window: WallpaperPanel?
    private var globalClickMonitor: Any?
    private var localClickMonitor: Any?
    private let model: AppModel

    init(model: AppModel) {
        self.model = model
        window = makeWindow()
    }

    deinit { removeClickMonitors() }

    func toggle() {
        guard let window else { return }
        if window.isVisible { hide(); return }
        NSApp.activate(ignoringOtherApps: true)
        window.center(); window.makeKeyAndOrderFront(nil); window.orderFrontRegardless()
        installClickMonitors()
    }

    func show() { toggle() }

    private func hide() { window?.orderOut(nil); removeClickMonitors() }

    private func installClickMonitors() {
        removeClickMonitors()
        globalClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in self?.hide() }
        localClickMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            guard let self, let window = self.window else { return event }
            let point = NSEvent.mouseLocation
            if !window.frame.contains(point) { self.hide() }
            return event
        }
    }

    private func removeClickMonitors() {
        if let globalClickMonitor { NSEvent.removeMonitor(globalClickMonitor); self.globalClickMonitor = nil }
        if let localClickMonitor { NSEvent.removeMonitor(localClickMonitor); self.localClickMonitor = nil }
    }

    private func makeWindow() -> WallpaperPanel {
        let view = WallpaperGalleryView(model: model, standalone: true)
        let window = WallpaperPanel(contentRect: NSRect(x: 0, y: 0, width: 940, height: 520), styleMask: [.borderless], backing: .buffered, defer: false)
        window.backgroundColor = .clear; window.isOpaque = false; window.hasShadow = true
        window.level = NSWindow.Level(rawValue: NSWindow.Level.floating.rawValue + 1)
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.hidesOnDeactivate = false; window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: view)
        window.onCancel = { [weak self] in self?.hide() }
        window.center()
        return window
    }
}

private final class WallpaperPanel: NSPanel {
    var onCancel: (() -> Void)?
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
    override func cancelOperation(_ sender: Any?) { onCancel?() }
}
