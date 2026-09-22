import AppKit
import SwiftUI
import QuartzCore

final class SidePanelController {
    private let model: AppModel
    private var leftPanel: FloatingPanel?
    private var rightPanel: FloatingPanel?
    private var activityMonitor: Any?
    private var inactivityTask: DispatchWorkItem?
    init(model: AppModel) {
        self.model = model
        // Build both trees once at launch. The first click now only positions
        // and animates an existing panel instead of compiling a large SwiftUI tree.
        self.leftPanel = makePanel(side: .left)
        self.rightPanel = makePanel(side: .right)
        activityMonitor = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved, .leftMouseDown, .rightMouseDown, .keyDown, .scrollWheel]) { [weak self] event in
            if self?.rightPanel?.isVisible == true { self?.resetControlsInactivityTimer() }
            return event
        }
    }

    deinit {
        inactivityTask?.cancel()
        if let activityMonitor { NSEvent.removeMonitor(activityMonitor) }
    }

    func toggleLeft() {
        if let rightPanel, rightPanel.isVisible { dismiss(rightPanel, side: .right) }
        if let leftPanel, leftPanel.isVisible { dismiss(leftPanel, side: .left); return }
        let panel = leftPanel ?? makePanel(side: .left)
        leftPanel = panel; present(panel, side: .left)
    }
    func toggleRight(detail: String = "") {
        if let leftPanel, leftPanel.isVisible { dismiss(leftPanel, side: .left) }
        if let rightPanel, rightPanel.isVisible && model.rightSidebarDetail == detail { dismiss(rightPanel, side: .right); return }
        model.rightSidebarDetail = detail
        switch detail { case "Wi-Fi": model.controls.requestWiFiAccessAndScan(); case "Sound": model.controls.refreshAudioDevices(); case "Battery": model.controls.refreshPowerState(); default: model.controls.refreshAll() }
        let panel = rightPanel ?? makePanel(side: .right)
        rightPanel = panel; present(panel, side: .right)
    }

    private func resetControlsInactivityTimer() {
        inactivityTask?.cancel()
        let task = DispatchWorkItem { [weak self] in
            guard let self, let rightPanel = self.rightPanel, rightPanel.isVisible else { return }
            self.dismiss(rightPanel, side: .right)
        }
        inactivityTask = task
        DispatchQueue.main.asyncAfter(deadline: .now() + 12, execute: task)
    }

    private enum Side { case left, right }
    private func makePanel(side: Side) -> FloatingPanel {
        let panel = FloatingPanel(contentRect: .zero, styleMask: [.borderless], backing: .buffered, defer: false)
        panel.level = .floating; panel.backgroundColor = .clear; panel.isOpaque = false; panel.hasShadow = true; panel.acceptsMouseMovedEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]; panel.isReleasedWhenClosed = false
        panel.onCancel = { [weak self, weak panel] in if let self, let panel { self.dismiss(panel, side: side) } }
        let close = { [weak self, weak panel] in if let self, let panel { self.dismiss(panel, side: side) } }
        panel.contentView = NSHostingView(rootView: side == .left ? AnyView(LeftSidebarView(model: model, close: close)) : AnyView(RightSidebarView(model: model, close: close)))
        return panel
    }
    private func targetFrame(side: Side) -> NSRect {
        guard let screen = NSScreen.main else { return .zero }
        let screenFrame = screen.visibleFrame
        let margin: CGFloat = 7
        let bar = model.configuration.bar
        let shelf = bar.notchMaskEnabled ? (bar.notchMaskHeight > 0 ? bar.notchMaskHeight : Double(screen.safeAreaInsets.top)) : 0
        let barClearance = bar.enabled && bar.position == .top ? CGFloat(bar.height + bar.outerInset * 2 + shelf) + 6 : 18
        let top = min(screenFrame.maxY - 10, screen.frame.maxY - barClearance)
        let width: CGFloat = 420
        let x = side == .left ? screenFrame.minX + margin : screenFrame.maxX - width - margin
        return NSRect(x: x, y: screenFrame.minY + margin, width: width, height: max(320, top - screenFrame.minY - margin))
    }
    private func present(_ panel: NSPanel, side: Side) {
        let target = targetFrame(side: side)
        let reduced = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        panel.setFrame(target, display: true)
        panel.contentView?.wantsLayer = true
        guard let layer = panel.contentView?.layer else { panel.makeKeyAndOrderFront(nil); return }
        layer.removeAllAnimations()
        layer.transform = reduced ? CATransform3DIdentity : CATransform3DMakeTranslation(side == .left ? -24 : 24, 0, 0)
        layer.opacity = reduced ? 1 : 0
        NSApp.activate(ignoringOtherApps: true); panel.makeKeyAndOrderFront(nil); panel.orderFrontRegardless()
        if side == .right { resetControlsInactivityTimer() } else { inactivityTask?.cancel() }
        guard !reduced else { return }
        let timing = CAMediaTimingFunction(controlPoints: 0.22, 1, 0.36, 1)
        let movement = CABasicAnimation(keyPath: "transform")
        movement.fromValue = NSValue(caTransform3D: layer.transform); movement.toValue = NSValue(caTransform3D: CATransform3DIdentity)
        movement.duration = 0.24; movement.timingFunction = timing
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = 0; fade.toValue = 1; fade.duration = 0.18; fade.timingFunction = timing
        layer.transform = CATransform3DIdentity; layer.opacity = 1
        layer.add(movement, forKey: "ryft.panel.open.transform"); layer.add(fade, forKey: "ryft.panel.open.opacity")
    }
    private func dismiss(_ panel: NSPanel, side: Side) {
        guard panel.isVisible else { return }
        inactivityTask?.cancel()
        guard !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion, let layer = panel.contentView?.layer else { panel.orderOut(nil); return }
        layer.removeAllAnimations()
        let endTransform = CATransform3DMakeTranslation(side == .left ? -18 : 18, 0, 0)
        let timing = CAMediaTimingFunction(controlPoints: 0.25, 1, 0.5, 1)
        let movement = CABasicAnimation(keyPath: "transform")
        movement.fromValue = NSValue(caTransform3D: CATransform3DIdentity); movement.toValue = NSValue(caTransform3D: endTransform)
        movement.duration = 0.17; movement.timingFunction = timing
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = 1; fade.toValue = 0; fade.duration = 0.15; fade.timingFunction = timing
        CATransaction.begin()
        CATransaction.setCompletionBlock { panel.orderOut(nil); layer.removeAllAnimations(); layer.transform = CATransform3DIdentity; layer.opacity = 1 }
        layer.add(movement, forKey: "ryft.panel.close.transform"); layer.add(fade, forKey: "ryft.panel.close.opacity")
        CATransaction.commit()
    }
}

final class FloatingPanel: NSPanel {
    var onCancel: (() -> Void)?
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
    override func cancelOperation(_ sender: Any?) { onCancel?() }
}
