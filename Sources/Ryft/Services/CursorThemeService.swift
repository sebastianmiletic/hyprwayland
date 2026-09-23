import AppKit
import CoreGraphics

/// Experimental system-wide cursor overlay. macOS has no public cursor-theme
/// API, so Ryft hides the native pointer and follows its global position with
/// the source configuration's Bibata Modern Classic pointer. Disabling the
/// option, quitting, or deinitializing always restores the native cursor.
final class CursorThemeService {
    static let shared = CursorThemeService()
    private var panel: NSPanel?
    private var timer: DispatchSourceTimer?
    private var hiddenDisplays = Set<CGDirectDisplayID>()
    private(set) var enabled = false

    private init() {}
    deinit { setEnabled(false) }

    func setEnabled(_ value: Bool) {
        guard value != enabled else { return }
        enabled = value
        value ? start() : stop()
    }

    private func start() {
        guard let imageURL = Bundle.module.url(forResource: "bibata-modern-classic-pointer", withExtension: "png"),
              let source = NSImage(contentsOf: imageURL) else { enabled = false; return }
        let image = blackCursorImage(from: source)
        let size = NSSize(width: 28, height: 28)
        let panel = NSPanel(contentRect: NSRect(origin: .zero, size: size), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.cursorWindow)) + 1)
        panel.backgroundColor = .clear; panel.isOpaque = false; panel.hasShadow = false; panel.ignoresMouseEvents = true; panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        let imageView = NSImageView(frame: NSRect(origin: .zero, size: size))
        imageView.image = image; imageView.imageScaling = .scaleProportionallyUpOrDown
        panel.contentView = imageView
        self.panel = panel
        refreshDisplays()
        movePointer(); panel.orderFrontRegardless()
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now(), repeating: .milliseconds(8), leeway: .milliseconds(2))
        timer.setEventHandler { [weak self] in self?.movePointer() }
        timer.resume(); self.timer = timer
    }

    func suspendOverlay() { panel?.orderOut(nil) }
    func resumeOverlay() { guard enabled else { return }; movePointer(); panel?.orderFrontRegardless() }

    private func stop() {
        timer?.cancel(); timer = nil
        panel?.orderOut(nil); panel = nil
        for display in hiddenDisplays { CGDisplayShowCursor(display) }
        hiddenDisplays.removeAll()
    }

    private func refreshDisplays() {
        let current = Set(NSScreen.screens.compactMap { screen -> CGDirectDisplayID? in
            (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber).map { CGDirectDisplayID($0.uint32Value) }
        })
        for display in current.subtracting(hiddenDisplays) where CGDisplayHideCursor(display) == .success { hiddenDisplays.insert(display) }
        for display in hiddenDisplays.subtracting(current) { CGDisplayShowCursor(display); hiddenDisplays.remove(display) }
    }

    private func movePointer() {
        guard enabled, let panel else { return }
        refreshDisplays()
        let point = NSEvent.mouseLocation
        // Bibata's arrow tip is inset in its source canvas.
        let origin = NSPoint(x: point.x - 4.5, y: point.y - 25.5)
        panel.setFrameOrigin(origin)
        if !panel.isVisible { panel.orderFrontRegardless() }
    }

    private func blackCursorImage(from source: NSImage) -> NSImage {
        let image = NSImage(size: source.size)
        image.lockFocus()
        source.draw(in: NSRect(origin: .zero, size: source.size), from: .zero, operation: .sourceOver, fraction: 1)
        NSColor(calibratedWhite: 0.04, alpha: 1).setFill()
        NSRect(origin: .zero, size: source.size).fill(using: .sourceIn)
        image.unlockFocus()
        return image
    }
}
