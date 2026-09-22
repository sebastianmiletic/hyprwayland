import AppKit
import SwiftUI
import QuartzCore

final class SidePanelController {
    private let model: AppModel
    private var leftPanel: FloatingPanel?
    private var rightPanel: FloatingPanel?
    private var globalScrollMonitor: Any?
    private var localScrollMonitor: Any?
    private var horizontalScroll: CGFloat = 0
    private var swipeTriggered = false
    private var lastSwipeAction = Date.distantPast
    init(model: AppModel) {
        self.model = model
        // Build both trees once at launch. The first click now only positions
        // and animates an existing panel instead of compiling a large SwiftUI tree.
        self.leftPanel = makePanel(side: .left)
        self.rightPanel = makePanel(side: .right)
        installSwipeMonitors()
    }

    deinit {
        if let globalScrollMonitor { NSEvent.removeMonitor(globalScrollMonitor) }
        if let localScrollMonitor { NSEvent.removeMonitor(localScrollMonitor) }
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

    private func installSwipeMonitors() {
        globalScrollMonitor = NSEvent.addGlobalMonitorForEvents(matching: .scrollWheel) { [weak self] in self?.handleScroll($0) }
        localScrollMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in self?.handleScroll(event); return event }
    }

    private func handleScroll(_ event: NSEvent) {
        if event.phase == .ended || event.phase == .cancelled || event.momentumPhase == .ended {
            horizontalScroll = 0; swipeTriggered = false; return
        }
        guard event.hasPreciseScrollingDeltas, abs(event.scrollingDeltaX) > abs(event.scrollingDeltaY) * 1.15 else { return }
        if event.phase == .began { horizontalScroll = 0; swipeTriggered = false }
        guard !swipeTriggered else { return }
        horizontalScroll += event.scrollingDeltaX
        guard abs(horizontalScroll) > 24, Date().timeIntervalSince(lastSwipeAction) > 0.45 else { return }
        swipeTriggered = true; lastSwipeAction = Date(); let direction = horizontalScroll
        DispatchQueue.main.async { [weak self] in
            if direction < 0 { self?.toggleRight() } else { self?.toggleLeft() }
        }
    }

    private enum Side { case left, right }
    private func makePanel(side: Side) -> FloatingPanel {
        let panel = FloatingPanel(contentRect: .zero, styleMask: [.borderless], backing: .buffered, defer: false)
        panel.level = .floating; panel.backgroundColor = .clear; panel.isOpaque = false; panel.hasShadow = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]; panel.isReleasedWhenClosed = false
        panel.onCancel = { [weak self, weak panel] in if let self, let panel { self.dismiss(panel, side: side) } }
        let close = { [weak self, weak panel] in if let self, let panel { self.dismiss(panel, side: side) } }
        panel.contentView = NSHostingView(rootView: side == .left ? AnyView(LeftSidebarView(model: model, close: close)) : AnyView(RightSidebarView(model: model, close: close)))
        return panel
    }
    private func targetFrame(side: Side) -> NSRect {
        guard let screen = NSScreen.main else { return .zero }
        let screenFrame = screen.visibleFrame
        let margin: CGFloat = 5
        let width: CGFloat = 420
        let x = side == .left ? screenFrame.minX + margin : screenFrame.maxX - width - margin
        return NSRect(x: x, y: screenFrame.minY + margin, width: width, height: screenFrame.height - margin * 2)
    }
    private func present(_ panel: NSPanel, side: Side) {
        let target = targetFrame(side: side)
        let reduced = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        var start = target; start.origin.x += side == .left ? -22 : 22
        panel.setFrame(reduced ? target : start, display: true); panel.alphaValue = reduced ? 1 : 0
        NSApp.activate(ignoringOtherApps: true); panel.makeKeyAndOrderFront(nil); panel.orderFrontRegardless()
        guard !reduced else { return }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.21; context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().setFrame(target, display: true); panel.animator().alphaValue = 1
        }
    }
    private func dismiss(_ panel: NSPanel, side: Side) {
        guard panel.isVisible else { return }
        if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion { panel.orderOut(nil); return }
        var target = panel.frame; target.origin.x += side == .left ? -16 : 16
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.22; context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().setFrame(target, display: true); panel.animator().alphaValue = 0
        }, completionHandler: { panel.orderOut(nil); panel.alphaValue = 1 })
    }
}

final class FloatingPanel: NSPanel {
    var onCancel: (() -> Void)?
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
    override func cancelOperation(_ sender: Any?) { onCancel?() }
}
