import AppKit
import QuartzCore

/// Owns Ryft-initiated Space transitions. The outgoing display is held above
/// application windows while SkyLight switches directly underneath it, then
/// slides away. Ryft's stationary bar remains above these overlays.
final class WorkspaceTransitionController {
    private var panels: [NSPanel] = []
    private var transitionID = UUID()

    func perform(direction: Int, switchAction: () -> Bool) -> Bool {
        guard CGPreflightScreenCaptureAccess() else { return false }
        cleanup()
        let restoreCursor = CursorThemeService.shared.enabled
        if restoreCursor { CursorThemeService.shared.suspendOverlay() }
        defer { if restoreCursor { CursorThemeService.shared.resumeOverlay() } }
        let captures: [(NSScreen, CGImage)] = NSScreen.screens.compactMap { screen in
            guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber,
                  let image = CGDisplayCreateImage(CGDirectDisplayID(number.uint32Value)) else { return nil }
            return (screen, image)
        }
        guard captures.count == NSScreen.screens.count, !captures.isEmpty else { return false }
        let id = UUID(); transitionID = id
        panels = captures.map { screen, image in makePanel(screen: screen, image: image) }
        panels.forEach { $0.orderFrontRegardless() }
        guard switchAction() else { cleanup(); return false }
        let reduced = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.025) { [weak self] in
            guard let self, self.transitionID == id else { return }
            for panel in self.panels {
                guard let layer = panel.contentView?.layer else { continue }
                let animation: CABasicAnimation
                if reduced {
                    animation = CABasicAnimation(keyPath: "opacity"); animation.fromValue = 1; animation.toValue = 0
                    CATransaction.begin(); CATransaction.setDisableActions(true); layer.opacity = 0; CATransaction.commit()
                } else {
                    let distance = panel.frame.width * CGFloat(direction >= 0 ? -1 : 1)
                    let end = CATransform3DMakeTranslation(distance, 0, 0)
                    animation = CABasicAnimation(keyPath: "transform"); animation.fromValue = NSValue(caTransform3D: CATransform3DIdentity); animation.toValue = NSValue(caTransform3D: end)
                    CATransaction.begin(); CATransaction.setDisableActions(true); layer.transform = end; CATransaction.commit()
                }
                animation.duration = reduced ? 0.1 : 0.22
                animation.timingFunction = CAMediaTimingFunction(controlPoints: 0.22, 1, 0.36, 1)
                layer.add(animation, forKey: "ryft.workspace.transition")
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + (reduced ? 0.11 : 0.23)) { [weak self] in
                guard self?.transitionID == id else { return }
                self?.cleanup()
            }
        }
        return true
    }

    private func makePanel(screen: NSScreen, image: CGImage) -> NSPanel {
        let panel = NSPanel(contentRect: screen.frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 1)
        panel.backgroundColor = .clear; panel.isOpaque = false; panel.hasShadow = false; panel.ignoresMouseEvents = true; panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        let view = NSView(frame: NSRect(origin: .zero, size: screen.frame.size)); view.wantsLayer = true
        view.layer?.contents = image; view.layer?.contentsGravity = .resizeAspectFill; view.layer?.contentsScale = screen.backingScaleFactor
        panel.contentView = view
        return panel
    }

    private func cleanup() {
        transitionID = UUID()
        panels.forEach { $0.orderOut(nil); $0.contentView?.layer?.removeAllAnimations() }
        panels.removeAll()
    }
}
