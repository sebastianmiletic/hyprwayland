import SwiftUI
import UniformTypeIdentifiers

private enum BarImageCache {
    static let images = NSCache<NSString, NSImage>()
    static func image(at path: String) -> NSImage? {
        guard !path.isEmpty else { return nil }
        if let cached = images.object(forKey: path as NSString) { return cached }
        guard let image = NSImage(contentsOfFile: path) else { return nil }
        images.setObject(image, forKey: path as NSString); return image
    }
}

struct BarView: View {
    @ObservedObject var model: AppModel
    @ObservedObject private var system: SystemMonitor
    @ObservedObject private var workspaces: WorkspaceService
    let notchWidth: Double
    let topReservedHeight: Double
    let configurationOverride: BarConfiguration?
    let interactionID: UUID?
    let editing: Bool
    let onSelectWidget: ((UUID) -> Void)?

    init(model: AppModel, notchWidth: Double = 0, topReservedHeight: Double = 0, configurationOverride: BarConfiguration? = nil, interactionID: UUID? = nil, editing: Bool = false, onSelectWidget: ((UUID) -> Void)? = nil) {
        self.model = model; self.system = model.system; self.workspaces = model.workspaces; self.notchWidth = notchWidth; self.topReservedHeight = topReservedHeight; self.configurationOverride = configurationOverride; self.interactionID = interactionID; self.editing = editing; self.onSelectWidget = onSelectWidget
    }
    private var config: BarConfiguration { configurationOverride ?? model.configuration.bar }
    private var palette: ThemePalette { config.palette }
    private func widgets(_ placement: WidgetPlacement) -> [WidgetConfiguration] { config.widgets.filter { $0.enabled && $0.placement == placement } }

    var body: some View {
        GeometryReader { proxy in
            let contentInset: Double = 12
            let outerX = config.connectedPanel ? 0 : (config.floating ? config.horizontalInset : 0)
            let barWidth = max(0, proxy.size.width - outerX * 2)
            let barHeight = max(0, proxy.size.height - topReservedHeight - config.outerInset * 2)
            let sideWidth = max(0, (barWidth - contentInset * 2 - effectiveNotchWidth) / 2)
            ZStack(alignment: .top) {
                if topReservedHeight > 0 {
                    TrueBlackView().frame(width: proxy.size.width, height: topReservedHeight)
                }
                ZStack {
                    barBackground
                    HStack(spacing: 0) {
                        HStack(spacing: config.itemSpacing) {
                            zone(.leading)
                            Spacer(minLength: 3)
                            zone(.beforeNotch)
                        }
                        .frame(width: sideWidth, alignment: .leading)
                        Color.clear.frame(width: effectiveNotchWidth).accessibilityHidden(true)
                        HStack(spacing: config.itemSpacing) {
                            zone(.afterNotch)
                            Spacer(minLength: 3)
                            zone(.trailing)
                        }
                        .frame(width: sideWidth, alignment: .trailing)
                    }
                    .padding(.horizontal, contentInset)
                }
                .frame(width: barWidth, height: barHeight)
                .position(x: proxy.size.width / 2, y: topReservedHeight + barHeight / 2 + config.outerInset)
            }
        }
        .font(.system(size: 12.5, weight: .medium, design: .rounded))
        .foregroundStyle(Color(hex: palette.foreground))
    }

    private var effectiveNotchWidth: Double { notchWidth > 0 ? notchWidth + 16 : 8 }
    private var barShape: RoundedRectangle { RoundedRectangle(cornerRadius: config.connectedPanel ? 0 : (config.floating ? config.cornerRadius : 0), style: .continuous) }
    @ViewBuilder private var barSurface: some View {
        if config.blurEnabled {
            ZStack {
                if let image = BarImageCache.image(at: model.configuration.currentWallpaper) {
                    Image(nsImage: image).resizable().scaledToFill().blur(radius: blurRadius).scaleEffect(1.08)
                } else { Color(hex: palette.background) }
                Color(hex: palette.background).opacity(config.opacity)
            }.clipShape(barShape)
                .overlay(barShape.stroke(Color(hex: palette.muted).opacity(0.3), lineWidth: config.floating ? 1 : 0))
        } else {
            barShape.fill(Color(hex: palette.background).opacity(config.opacity))
                .overlay(barShape.stroke(Color(hex: palette.muted).opacity(0.22), lineWidth: config.floating ? 1 : 0))
        }
    }
    private var blurRadius: CGFloat { switch config.blurStyle { case .thin: 8; case .regular: 16; case .thick: 28 } }
    @ViewBuilder private var barBackground: some View {
        if !config.showBackground && !config.connectedPanel {
            Color.clear
        } else if config.splitAroundNotch && !config.connectedPanel && notchWidth > 0 {
            HStack(spacing: effectiveNotchWidth) { barSurface; barSurface }
        } else { barSurface }
    }

    private func zone(_ placement: WidgetPlacement) -> some View {
        HStack(spacing: config.itemSpacing) {
            ForEach(widgets(placement)) { widget in
                if widget.kind == .spacer { Spacer(minLength: 8) }
                else if editing {
                    WidgetView(model: model, system: system, controls: model.controls, workspaces: workspaces, widget: widget, interactionID: nil, actionEnabled: false)
                        .fixedSize(horizontal: true, vertical: false)
                        .contentShape(Rectangle())
                        .onTapGesture { onSelectWidget?(widget.id) }
                        .onDrag { NSItemProvider(object: widget.id.uuidString as NSString) }
                        .onDrop(of: [UTType.text], delegate: WidgetZoneDropDelegate(model: model, placement: placement, before: widget.id, enabled: true))
                } else {
                    WidgetView(model: model, system: system, controls: model.controls, workspaces: workspaces, widget: widget, interactionID: interactionID, actionEnabled: interactionID != nil)
                        .fixedSize(horizontal: true, vertical: false)
                }
            }
        }
        .frame(minHeight: 34)
        .contentShape(Rectangle())
        .modifier(ZoneDropModifier(model: model, placement: placement, enabled: editing))
    }
}

private struct ZoneDropModifier: ViewModifier {
    let model: AppModel
    let placement: WidgetPlacement
    let enabled: Bool
    @ViewBuilder func body(content: Content) -> some View {
        if enabled { content.onDrop(of: [UTType.text], delegate: WidgetZoneDropDelegate(model: model, placement: placement, enabled: true)) }
        else { content }
    }
}

private struct WidgetZoneDropDelegate: DropDelegate {
    let model: AppModel
    let placement: WidgetPlacement
    var before: UUID? = nil
    let enabled: Bool

    func validateDrop(info: DropInfo) -> Bool { enabled && info.hasItemsConforming(to: [UTType.text]) }
    func dropUpdated(info: DropInfo) -> DropProposal? { DropProposal(operation: .move) }
    func performDrop(info: DropInfo) -> Bool {
        guard enabled, let provider = info.itemProviders(for: [UTType.text]).first else { return false }
        provider.loadObject(ofClass: NSString.self) { object, _ in
            guard let value = object as? NSString, let id = UUID(uuidString: value as String) else { return }
            DispatchQueue.main.async {
                let changes = {
                    guard let source = model.configuration.bar.widgets.firstIndex(where: { $0.id == id }) else { return }
                    var moved = model.configuration.bar.widgets.remove(at: source)
                    moved.placement = placement
                    if let before, let target = model.configuration.bar.widgets.firstIndex(where: { $0.id == before }) {
                        model.configuration.bar.widgets.insert(moved, at: target)
                    } else {
                        let lastInZone = model.configuration.bar.widgets.lastIndex(where: { $0.placement == placement })
                        model.configuration.bar.widgets.insert(moved, at: lastInZone.map { $0 + 1 } ?? model.configuration.bar.widgets.endIndex)
                    }
                }
                if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion { changes() }
                else { withAnimation(.easeOut(duration: 0.2), changes) }
            }
        }
        return true
    }
}

private struct WidgetView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var system: SystemMonitor
    @ObservedObject var controls: SystemControlService
    @ObservedObject var workspaces: WorkspaceService
    let widget: WidgetConfiguration
    let interactionID: UUID?
    let actionEnabled: Bool
    private var palette: ThemePalette { model.configuration.bar.palette }

    @ViewBuilder var body: some View {
        if widget.kind == .workspaces {
            content.modifier(WidgetChrome(widget: widget, palette: palette)).accessibilityLabel(widget.name).help(widget.name)
        } else if widget.kind == .rightSidebar {
            content.modifier(WidgetChrome(widget: widget, palette: palette)).accessibilityLabel(widget.name).help(widget.name)
                .popover(isPresented: popoverPresented, arrowEdge: .top) { statusPopover }
        } else if widget.kind == .battery {
            Button { if actionEnabled { controls.setLowPowerMode(!controls.lowPowerMode) } } label: { content.modifier(WidgetChrome(widget: widget, palette: palette)) }
                .buttonStyle(.plain).accessibilityLabel("Toggle Low Power Mode").help(controls.lowPowerMode ? "Turn Low Power Mode off" : "Turn Low Power Mode on")
        } else if [.wifi, .volume].contains(widget.kind) {
            Button { if actionEnabled { showStatusPopover(for: widget.kind) } } label: { content.modifier(WidgetChrome(widget: widget, palette: palette)) }
                .buttonStyle(.plain).accessibilityLabel(widget.name).help(widget.name)
                .popover(isPresented: popoverPresented, arrowEdge: .top) { statusPopover }
        } else {
            content.modifier(WidgetChrome(widget: widget, palette: palette))
                .contentShape(Rectangle())
                .onTapGesture { if actionEnabled { performAction() } }
                .accessibilityAddTraits(.isButton).accessibilityLabel(widget.name).help(widget.name)
        }
    }

    @ViewBuilder private var content: some View {
        switch widget.kind {
        case .workspaces:
            HStack(spacing: 2) {
                ForEach(1...max(workspaces.canReadSpaces ? workspaces.desktopCount : model.configuration.bar.workspaceCount, 1), id: \.self) { number in
                    Button {
                        if actionEnabled { workspaces.switchTo(number) { model.statusMessage = $0 } }
                    } label: {
                        Text("\(number)").font(.system(size: 11, weight: .semibold, design: .rounded)).frame(width: 22, height: 22)
                            .background(number == workspaces.currentDesktop ? Color(hex: palette.accent) : .clear)
                            .foregroundStyle(number == workspaces.currentDesktop ? Color(hex: palette.background) : Color(hex: palette.muted)).clipShape(Circle()).frame(width: 26, height: 26)
                    }.buttonStyle(.plain).accessibilityLabel("Desktop \(number)")
                }
            }
        case .clock:
            TimelineView(.periodic(from: .now, by: 1)) { context in
                widgetLabel(context.date.formatted(date: .abbreviated, time: .shortened)).monospacedDigit()
            }
        case .leftSidebar: widgetLabel("Tools")
        case .activeApp: widgetLabel(system.activeApp)
        case .wifi: widgetLabel(system.wifi)
        case .battery:
            HStack(spacing: 5) {
                if widget.showIcon {
                    Image(systemName: batterySymbol).foregroundStyle(batteryColor)
                }
                if widget.showLabel { Text(controls.batteryPercent).lineLimit(1) }
            }
        case .volume: widgetLabel("\(Int(controls.outputVolume))%")
        case .uptime: widgetLabel("CPU \(system.cpu) · RAM \(system.memory)")
        case .rightSidebar:
            if model.configuration.bar.sourceExact {
                HStack(spacing: 12) {
                    detailButton(batterySymbol, detail: "Battery", color: batteryColor)
                    detailButton("keyboard", detail: "")
                    detailButton("wifi", detail: "Wi-Fi")
                    detailButton(controls.outputVolume == 0 ? "speaker.slash.fill" : "speaker.wave.2.fill", detail: "Sound")
                }.font(.system(size: 13, weight: .medium))
            } else { widgetLabel("Controls") }
        case .settings: widgetLabel("Settings")
        case .customScript: ScriptWidgetLabel(widget: widget, palette: palette)
        case .spacer: EmptyView()
        }
    }

    private var batterySymbol: String {
        if controls.batteryCharging { return "battery.100percent.bolt" }
        switch controls.batteryLevel { case 90...: return "battery.100percent"; case 65..<90: return "battery.75percent"; case 40..<65: return "battery.50percent"; case 15..<40: return "battery.25percent"; default: return "battery.0percent" }
    }
    private var batteryColor: Color { controls.lowPowerMode ? .yellow : .white }
    private var popoverPresented: Binding<Bool> {
        Binding(get: { model.statusPopoverWidgetID == widget.id && model.statusPopoverInteractionID == interactionID }, set: { if !$0 { model.statusPopoverWidgetID = nil; model.statusPopoverInteractionID = nil; model.statusPopoverDetail = "" } })
    }
    @ViewBuilder private var statusPopover: some View {
        if model.statusPopoverWidgetID == widget.id && model.statusPopoverInteractionID == interactionID { StatusQuickPopover(model: model, detail: model.statusPopoverDetail).frame(width: 300) }
    }
    private func showStatusPopover(for kind: WidgetKind) {
        switch kind {
        case .wifi: model.statusPopoverDetail = "Wi-Fi"; model.statusPopoverInteractionID = interactionID; model.statusPopoverWidgetID = widget.id; controls.requestWiFiAccessAndScan()
        case .volume: model.statusPopoverDetail = "Sound"; model.statusPopoverInteractionID = interactionID; model.statusPopoverWidgetID = widget.id; controls.refreshAudioDevices()
        case .battery: model.statusPopoverDetail = "Battery"; model.statusPopoverInteractionID = interactionID; model.statusPopoverWidgetID = widget.id; controls.refreshPowerState()
        default: break
        }
    }
    private func detailButton(_ icon: String, detail: String, color: Color? = nil) -> some View {
        Button {
            guard actionEnabled else { return }
            if detail == "Battery" { controls.setLowPowerMode(!controls.lowPowerMode) }
            else if detail.isEmpty { NotificationCenter.default.post(name: .waycodeToggleRightSidebar, object: nil) }
            else { model.statusPopoverDetail = detail; model.statusPopoverInteractionID = interactionID; model.statusPopoverWidgetID = widget.id; if detail == "Wi-Fi" { controls.requestWiFiAccessAndScan() }; if detail == "Sound" { controls.refreshAudioDevices() } }
        } label: {
            Image(systemName: detail == "Battery" && controls.batteryCharging ? "battery.100percent.bolt" : icon).foregroundStyle(color ?? Color(hex: palette.foreground)).frame(width: 18, height: 24)
        }
            .buttonStyle(.plain).help(detail.isEmpty ? "Control center" : detail)
    }
    private func widgetLabel(_ value: String) -> some View {
        HStack(spacing: 6) {
            if widget.showIcon { WidgetIcon(value: widget.icon) }
            if widget.showLabel { Text(value).lineLimit(1) }
        }
    }
    private func performAction() {
        switch widget.clickAction {
        case .none: break
        case .leftSidebar: NotificationCenter.default.post(name: .waycodeToggleLeftSidebar, object: nil)
        case .rightSidebar:
            let detail: String
            switch widget.kind { case .wifi: detail = "Wi-Fi"; case .volume: detail = "Sound"; case .battery: detail = "Battery"; default: detail = "" }
            NotificationCenter.default.post(name: .waycodeToggleRightSidebar, object: detail)
        case .settings: NotificationCenter.default.post(name: .waycodeShowSettings, object: nil)
        case .wallpapers: NotificationCenter.default.post(name: .waycodeShowWallpapers, object: nil)
        case .randomWallpaper: model.randomWallpaper()
        case .shell: ScriptWidgetRunner.runAction(widget.clickCommand)
        }
    }
}

private struct StatusQuickPopover: View {
    @ObservedObject var model: AppModel
    @ObservedObject private var controls: SystemControlService
    let detail: String
    private var palette: ThemePalette { model.configuration.bar.palette }
    init(model: AppModel, detail: String) { self.model = model; self.controls = model.controls; self.detail = detail }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 9) {
                Image(systemName: icon).foregroundStyle(iconColor).frame(width: 26, height: 26).background(Color(hex: palette.surface)).clipShape(Circle())
                Text(detail).font(.system(size: 15, weight: .semibold, design: .rounded)); Spacer()
            }
            Rectangle().fill(Color(hex: palette.muted).opacity(0.25)).frame(height: 1)
            if detail == "Wi-Fi" { wifiContent }
            else if detail == "Sound" { soundContent }
            else { batteryContent }
            if !controls.operationMessage.isEmpty { Text(controls.operationMessage).font(.caption).foregroundStyle(Color(hex: palette.muted)).lineLimit(2) }
        }
        .padding(16).background(Color(hex: palette.background)).foregroundStyle(Color(hex: palette.foreground))
    }
    private var iconColor: Color {
        guard detail == "Battery" else { return Color(hex: palette.accent) }
        return controls.lowPowerMode ? .yellow : .white
    }
    private var icon: String {
        if detail == "Wi-Fi" { return "wifi" }; if detail == "Sound" { return "speaker.wave.2.fill" }
        if controls.batteryCharging { return "battery.100percent.bolt" }
        switch controls.batteryLevel { case 90...: return "battery.100percent"; case 65..<90: return "battery.75percent"; case 40..<65: return "battery.50percent"; case 15..<40: return "battery.25percent"; default: return "battery.0percent" }
    }
    private var wifiContent: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                Toggle("Wi-Fi", isOn: Binding(get: { controls.wifiEnabled }, set: controls.setWiFiEnabled)).toggleStyle(.switch).tint(Color(hex: palette.accent))
                Spacer(); Button { controls.requestWiFiAccessAndScan() } label: { if controls.scanningWiFi { ProgressView().controlSize(.small) } else { Image(systemName: "arrow.clockwise") } }.buttonStyle(.plain)
            }
            Text(controls.connectedSSID).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            ForEach(controls.wifiNetworks.prefix(4)) { network in
                VStack(spacing: 6) {
                    Button {
                        model.selectedWiFiID = network.id; model.wifiPassword = ""
                        if !network.secure { controls.connect(to: network, password: "") }
                    } label: {
                        HStack { Image(systemName: "wifi"); Text(network.ssid).lineLimit(1); Spacer(); if network.secure { Image(systemName: "lock.fill").font(.caption) } }
                            .padding(.horizontal, 10).frame(height: 34).background(Color(hex: palette.surface)).clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }.buttonStyle(.plain)
                    if model.selectedWiFiID == network.id && network.secure {
                        HStack { SecureField("Password", text: $model.wifiPassword).textFieldStyle(.plain).onSubmit { controls.connect(to: network, password: model.wifiPassword) }; Button("Connect") { controls.connect(to: network, password: model.wifiPassword) }.buttonStyle(QuickPopoverButtonStyle(palette: palette)) }
                            .padding(9).background(Color(hex: palette.surface)).clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                }
            }
            Button("Open Network Settings") { model.openSystemSettings("Network-Settings.extension") }.buttonStyle(QuickPopoverButtonStyle(palette: palette))
        }
    }
    private var soundContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack { Image(systemName: "speaker.wave.2.fill"); Slider(value: Binding(get: { controls.outputVolume }, set: controls.setOutputVolume), in: 0...100).tint(Color(hex: palette.accent)); Text("\(Int(controls.outputVolume))%").monospacedDigit().frame(width: 38) }
            HStack { Button("Mute") { controls.setMuted(true) }; Button("Unmute") { controls.setMuted(false) }; Spacer() }.buttonStyle(QuickPopoverButtonStyle(palette: palette))
            if !controls.audioDevices.isEmpty {
                Picker("Output", selection: Binding(get: { controls.defaultAudioDevice }, set: controls.selectAudioDevice)) {
                    ForEach(controls.audioDevices) { Text($0.name).tag($0.id) }
                }.pickerStyle(.menu).tint(Color(hex: palette.accent))
                    .padding(.horizontal, 10).frame(height: 34).background(Color(hex: palette.surface)).clipShape(RoundedRectangle(cornerRadius: 10))
            }
        }
    }
    private var batteryContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack { Image(systemName: "battery.75percent").font(.title); Text(controls.batteryPercent).font(.title2.weight(.semibold)); Spacer() }
            Toggle("Low Power Mode", isOn: Binding(get: { controls.lowPowerMode }, set: controls.setLowPowerMode)).toggleStyle(.switch).tint(Color(hex: palette.accent))
            Button("Open Battery Settings") { model.openSystemSettings("Battery-Settings.extension") }.buttonStyle(QuickPopoverButtonStyle(palette: palette))
        }
    }
}

private struct QuickPopoverButtonStyle: ButtonStyle {
    let palette: ThemePalette
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.system(size: 12, weight: .semibold))
            .padding(.horizontal, 10).frame(height: 30)
            .background(Color(hex: configuration.isPressed ? palette.accent : palette.surface))
            .foregroundStyle(Color(hex: configuration.isPressed ? palette.background : palette.foreground))
            .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
    }
}

private struct TrueBlackView: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView(); view.wantsLayer = true; view.layer?.backgroundColor = CGColor(gray: 0, alpha: 1); view.layer?.isOpaque = true
        return view
    }
    func updateNSView(_ view: NSView, context: Context) { view.layer?.backgroundColor = CGColor(gray: 0, alpha: 1); view.layer?.isOpaque = true }
}

struct SourcePressButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reducedMotion
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reducedMotion ? 0.96 : 1)
            .opacity(configuration.isPressed ? 0.78 : 1)
            .animation(.easeOut(duration: reducedMotion ? 0 : 0.12), value: configuration.isPressed)
    }
}

private struct WidgetChrome: ViewModifier {
    let widget: WidgetConfiguration
    let palette: ThemePalette
    func body(content: Content) -> some View {
        content
            .font(.system(size: widget.fontSize, weight: .medium, design: .rounded))
            .padding(.horizontal, widget.style == .plain ? min(3, widget.horizontalPadding) : widget.horizontalPadding)
            .frame(height: 34)
            .background(widget.style == .pill ? Color(hex: widget.background ?? palette.surface) : .clear)
            .clipShape(RoundedRectangle(cornerRadius: widget.cornerRadius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: widget.cornerRadius, style: .continuous).stroke(Color(hex: widget.foreground ?? palette.muted).opacity(0.45), lineWidth: widget.style == .outlined ? 1 : 0))
            .foregroundStyle(Color(hex: widget.foreground ?? palette.foreground))
    }
}

private struct ScriptWidgetLabel: View {
    let widget: WidgetConfiguration
    let palette: ThemePalette
    @ObservedObject private var runner: ScriptWidgetRunner
    init(widget: WidgetConfiguration, palette: ThemePalette) {
        self.widget = widget; self.palette = palette
        self.runner = ScriptWidgetRunner(command: widget.script, interval: widget.refreshInterval)
    }
    var body: some View {
        HStack(spacing: 6) {
            if widget.showIcon { WidgetIcon(value: widget.icon) }
            if widget.showLabel { Text(runner.output).lineLimit(1) }
        }
    }
}

struct WidgetIcon: View {
    let value: String
    var body: some View {
        if value.hasPrefix("text:") {
            Text(String(value.dropFirst(5))).lineLimit(1)
        } else if value.hasPrefix("bundle:"), let url = Bundle.module.url(forResource: String(value.dropFirst(7)), withExtension: nil), let image = NSImage(contentsOf: url) {
            Image(nsImage: image).resizable().scaledToFit().frame(width: 19.5, height: 19.5)
        } else if value.hasPrefix("/"), let image = NSImage(contentsOfFile: value) {
            Image(nsImage: image).resizable().scaledToFit().frame(width: 16, height: 16)
        } else {
            Image(systemName: value)
        }
    }
}

struct EditableBarCanvas: View {
    @ObservedObject var model: AppModel
    @Binding var selectedWidgetID: UUID?
    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .top) {
                LinearGradient(colors: [Color(hex: model.configuration.bar.palette.muted).opacity(0.28), Color(hex: model.configuration.bar.palette.background).opacity(0.7)], startPoint: .topLeading, endPoint: .bottomTrailing)
                BarView(model: model, notchWidth: model.configuration.bar.reserveNotchSpace && !model.configuration.bar.notchMaskEnabled ? min(180, proxy.size.width * 0.18) : 0, topReservedHeight: model.configuration.bar.notchMaskEnabled ? 32 : 0, editing: true) { selectedWidgetID = $0 }
                if model.configuration.bar.reserveNotchSpace && !model.configuration.bar.notchMaskEnabled {
                    RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color(nsColor: .black)).frame(width: min(164, proxy.size.width * 0.17), height: 34).offset(y: -10)
                }
                Text("Drag widgets directly on the bar. Drop near the center edges to move around the notch.")
                    .font(.caption).foregroundStyle(.white.opacity(0.82)).padding(.horizontal, 10).padding(.vertical, 6)
                    .background(.black.opacity(0.5)).clipShape(Capsule()).frame(maxHeight: .infinity, alignment: .bottom).padding(.bottom, 8)
            }
        }
        .frame(height: 122)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(.primary.opacity(0.1)))
    }
}

struct BarPreview: View {
    @ObservedObject var model: AppModel
    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .top) {
                LinearGradient(colors: [Color(hex: model.configuration.bar.palette.muted).opacity(0.34), Color(hex: model.configuration.bar.palette.background).opacity(0.72)], startPoint: .topLeading, endPoint: .bottomTrailing)
                BarView(model: model, notchWidth: model.configuration.bar.reserveNotchSpace && !model.configuration.bar.notchMaskEnabled ? min(180, proxy.size.width * 0.18) : 0, topReservedHeight: model.configuration.bar.notchMaskEnabled ? 32 : 0)
                if model.configuration.bar.reserveNotchSpace && !model.configuration.bar.notchMaskEnabled {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color(nsColor: .black)).frame(width: min(164, proxy.size.width * 0.17), height: 34).offset(y: -10)
                }
            }
        }
        .frame(height: max(86, model.configuration.bar.height + model.configuration.bar.outerInset * 2 + 28 + (model.configuration.bar.notchMaskEnabled ? 32 : 0)))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(.primary.opacity(0.1)))
    }
}
