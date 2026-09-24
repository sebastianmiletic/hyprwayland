import AppKit
import SwiftUI
import QuartzCore

final class SidePanelController {
    private let model: AppModel
    private var leftPanel: FloatingPanel?
    private var rightPanel: FloatingPanel?
    private var activityMonitor: Any?
    private var outsideClickMonitor: Any?
    private var inactivityTask: DispatchWorkItem?
    init(model: AppModel) {
        self.model = model
        // Build both trees once at launch. The first click now only positions
        // and animates an existing panel instead of compiling a large SwiftUI tree.
        self.leftPanel = makePanel(side: .left)
        self.rightPanel = makePanel(side: .right)
        activityMonitor = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved, .leftMouseDown, .rightMouseDown, .keyDown, .scrollWheel]) { [weak self] event in
            guard let self else { return event }
            if self.rightPanel?.isVisible == true { self.resetControlsInactivityTimer() }
            if event.type == .leftMouseDown || event.type == .rightMouseDown {
                if let panel = self.rightPanel, panel.isVisible, event.window !== panel { self.dismiss(panel, side: .right) }
                if let panel = self.leftPanel, panel.isVisible, event.window !== panel, !self.model.assistantPanelLocked { self.dismiss(panel, side: .left) }
            }
            return event
        }
        outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            guard let self else { return }
            if let panel = self.rightPanel, panel.isVisible { self.dismiss(panel, side: .right) }
            if let panel = self.leftPanel, panel.isVisible, !self.model.assistantPanelLocked { self.dismiss(panel, side: .left) }
        }
    }

    deinit {
        inactivityTask?.cancel()
        if let activityMonitor { NSEvent.removeMonitor(activityMonitor) }
        if let outsideClickMonitor { NSEvent.removeMonitor(outsideClickMonitor) }
    }

    func toggleLeft() {
        if let rightPanel, rightPanel.isVisible { dismiss(rightPanel, side: .right) }
        if let leftPanel, leftPanel.isVisible {
            if !model.assistantPanelLocked { dismiss(leftPanel, side: .left) }
            return
        }
        let panel = leftPanel ?? makePanel(side: .left)
        leftPanel = panel; present(panel, side: .left)
    }
    func toggleRight(detail: String = "") {
        if let leftPanel, leftPanel.isVisible, !model.assistantPanelLocked { dismiss(leftPanel, side: .left) }
        if let rightPanel, rightPanel.isVisible && model.rightSidebarDetail == detail { dismiss(rightPanel, side: .right); return }
        model.rightSidebarDetail = detail
        switch detail { case "Wi-Fi": model.controls.prepareWiFiMenu(); case "Sound": model.controls.prepareSoundMenu(); case "Battery": model.controls.operationMessage = ""; model.controls.refreshPowerState(); default: model.controls.operationMessage = ""; model.controls.refreshAll() }
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
        var usable = screen.visibleFrame
        let margin: CGFloat = 7
        let bar = model.configuration.bar
        if bar.enabled && bar.position != .top {
            let coverBottom = screen.frame.maxY - DisplayLayoutMetrics.menuBarHeight(for: screen)
            usable.size.height = max(0, min(usable.maxY, coverBottom) - usable.minY)
        }
        if bar.enabled {
            let shelf = bar.position == .top && bar.notchMaskEnabled ? (bar.notchMaskHeight > 0 ? bar.notchMaskHeight : Double(screen.safeAreaInsets.top)) : 0
            let barInsets = bar.presentation == .top ? 0 : bar.outerInset * 2
            let reserved = CGFloat(bar.height + barInsets + shelf) + 6
            switch bar.position {
            case .top: usable.size.height = max(0, min(usable.maxY, screen.frame.maxY - reserved) - usable.minY)
            case .bottom:
                let edge = screen.frame.minY + reserved; let removed = max(0, edge - usable.minY)
                usable.origin.y += removed; usable.size.height -= removed
            case .left:
                let edge = screen.frame.minX + reserved; let removed = max(0, edge - usable.minX)
                usable.origin.x += removed; usable.size.width -= removed
            case .right: usable.size.width = max(0, min(usable.maxX, screen.frame.maxX - reserved) - usable.minX)
            }
        }
        let width = min(CGFloat(420), max(320, usable.width - margin * 2))
        let x = side == .left ? usable.minX + margin : usable.maxX - width - margin
        return NSRect(x: x, y: usable.minY + margin, width: width, height: max(320, usable.height - margin * 2))
    }
    private func present(_ panel: FloatingPanel, side: Side) {
        let target = targetFrame(side: side)
        let reduced = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        let transitionID = UUID(); panel.transitionID = transitionID
        panel.setFrame(target, display: true)
        panel.contentView?.wantsLayer = true
        guard let layer = panel.contentView?.layer else { panel.makeKeyAndOrderFront(nil); return }
        layer.removeAllAnimations()
        let startTransform = CATransform3DMakeTranslation(side == .left ? -24 : 24, 0, 0)
        CATransaction.begin(); CATransaction.setDisableActions(true)
        layer.transform = reduced ? CATransform3DIdentity : startTransform
        layer.opacity = reduced ? 1 : 0
        CATransaction.commit()
        NSApp.activate(ignoringOtherApps: true); panel.makeKeyAndOrderFront(nil); panel.orderFrontRegardless()
        if side == .right { resetControlsInactivityTimer() } else { inactivityTask?.cancel() }
        guard !reduced, panel.transitionID == transitionID else { return }
        let timing = CAMediaTimingFunction(controlPoints: 0.22, 1, 0.36, 1)
        let movement = CABasicAnimation(keyPath: "transform")
        movement.fromValue = NSValue(caTransform3D: startTransform); movement.toValue = NSValue(caTransform3D: CATransform3DIdentity)
        movement.duration = 0.24; movement.timingFunction = timing
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = 0; fade.toValue = 1; fade.duration = 0.18; fade.timingFunction = timing
        CATransaction.begin(); CATransaction.setDisableActions(true)
        layer.transform = CATransform3DIdentity; layer.opacity = 1
        CATransaction.commit()
        layer.add(movement, forKey: "ryft.panel.open.transform"); layer.add(fade, forKey: "ryft.panel.open.opacity")
    }
    private func dismiss(_ panel: FloatingPanel, side: Side) {
        guard panel.isVisible else { return }
        inactivityTask?.cancel()
        let transitionID = UUID(); panel.transitionID = transitionID
        guard !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion, let layer = panel.contentView?.layer else { panel.orderOut(nil); return }
        let currentTransform = layer.presentation()?.transform ?? layer.transform
        let currentOpacity = layer.presentation()?.opacity ?? layer.opacity
        layer.removeAllAnimations()
        let endTransform = CATransform3DMakeTranslation(side == .left ? -18 : 18, 0, 0)
        let timing = CAMediaTimingFunction(controlPoints: 0.25, 1, 0.5, 1)
        let movement = CABasicAnimation(keyPath: "transform")
        movement.fromValue = NSValue(caTransform3D: currentTransform); movement.toValue = NSValue(caTransform3D: endTransform)
        movement.duration = 0.17; movement.timingFunction = timing
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = currentOpacity; fade.toValue = 0; fade.duration = 0.15; fade.timingFunction = timing
        CATransaction.begin(); CATransaction.setDisableActions(true)
        layer.transform = endTransform; layer.opacity = 0
        CATransaction.commit()
        CATransaction.begin()
        CATransaction.setCompletionBlock {
            guard panel.transitionID == transitionID else { return }
            panel.orderOut(nil); layer.removeAllAnimations()
            CATransaction.begin(); CATransaction.setDisableActions(true)
            layer.transform = CATransform3DIdentity; layer.opacity = 1
            CATransaction.commit()
        }
        layer.add(movement, forKey: "ryft.panel.close.transform"); layer.add(fade, forKey: "ryft.panel.close.opacity")
        CATransaction.commit()
    }
}

final class FloatingPanel: NSPanel {
    var onCancel: (() -> Void)?
    var transitionID = UUID()
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
    override func cancelOperation(_ sender: Any?) { onCancel?() }
}
