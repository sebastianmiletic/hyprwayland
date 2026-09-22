import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        NavigationSplitView {
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 9) {
                    ZStack { RoundedRectangle(cornerRadius: 8).fill(Color(hex: model.configuration.bar.palette.accent)); Image(systemName: "chevron.left.forwardslash.chevron.right").foregroundStyle(Color(hex: model.configuration.bar.palette.background)) }
                        .frame(width: 30, height: 30)
                    Text("Waycode").font(.system(size: 19, weight: .bold, design: .rounded))
                }.padding(.horizontal, 12).padding(.bottom, 12)
                ForEach(AppSection.allCases) { section in
                    Button { model.selectedSection = section } label: {
                        HStack(spacing: 10) { Image(systemName: section.symbol).frame(width: 18); Text(section.rawValue); Spacer() }
                            .padding(.horizontal, 11).frame(height: 36)
                            .background(model.selectedSection == section ? Color(hex: model.configuration.bar.palette.accent).opacity(0.18) : .clear)
                            .foregroundStyle(model.selectedSection == section ? Color.primary : Color.secondary)
                            .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                    }.buttonStyle(.plain)
                }
                Spacer()
                HStack { Circle().fill(Color(hex: model.configuration.bar.palette.success)).frame(width: 7, height: 7); Text(model.statusMessage).lineLimit(1); Spacer() }
                    .font(.caption).foregroundStyle(.secondary).padding(10).background(Color.primary.opacity(0.04)).clipShape(RoundedRectangle(cornerRadius: 9))
            }.padding(12).frame(minWidth: 190).background(Color.primary.opacity(0.025))
        } detail: {
            VStack(spacing: 0) {
                if model.selectedSection == .modules {
                    EditableBarCanvas(model: model, selectedWidgetID: $model.selectedEditorWidget)
                        .frame(maxWidth: 980).padding(.horizontal, 28).padding(.top, 20).padding(.bottom, 14)
                    Divider()
                }
                ScrollView {
                    VStack(alignment: .leading, spacing: 22) {
                        PageHeader(section: model.selectedSection)
                        page
                    }
                    .padding(28)
                    .frame(maxWidth: 860, alignment: .leading)
                    .frame(maxWidth: .infinity, alignment: .center)
                }
            }.background(Color.primary.opacity(0.015))
        }
        .frame(minWidth: 920, minHeight: 650)
    }

    @ViewBuilder private var page: some View {
        switch model.selectedSection {
        case .bar: BarSettingsView(model: model)
        case .themes: ThemeSettingsView(model: model)
        case .modules: ModuleSettingsView(model: model)
        case .tiling: TilingSettingsView(model: model)
        case .shortcuts: ShortcutSettingsView(model: model)
        case .wallpapers: WallpaperGalleryView(model: model, standalone: false)
        case .general: GeneralSettingsView(model: model)
        }
    }
}

private struct PageHeader: View {
    let section: AppSection
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(section.rawValue).font(.system(size: 27, weight: .bold, design: .rounded))
            Text(subtitle).foregroundStyle(.secondary)
        }
    }
    private var subtitle: String {
        switch section {
        case .bar: "Shape the live desktop bar. Changes appear immediately."
        case .themes: "Choose a preset or tune every color."
        case .modules: "Decide what earns space in the bar."
        case .tiling: "Hyprland-style window layouts using native macOS accessibility."
        case .shortcuts: "Map global controls that work from any app."
        case .wallpapers: "Pick an image for every connected display."
        case .general: "Profiles, permissions, and startup behavior."
        }
    }
}

struct SettingsGroup<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content
    init(_ title: String, @ViewBuilder content: () -> Content) { self.title = title; self.content = content() }
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title.uppercased()).font(.caption.weight(.semibold)).foregroundStyle(.secondary).tracking(0.7)
            content
        }.padding(18).background(Color.primary.opacity(0.045)).clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(.primary.opacity(0.08)))
    }
}

private struct CurrentBarInspector: View {
    @ObservedObject var model: AppModel
    private var bar: BarConfiguration { model.configuration.bar }
    private var screenWidth: CGFloat { NSScreen.main?.frame.width ?? 1440 }
    private var notchWidth: CGFloat {
        guard bar.reserveNotchSpace, !bar.notchMaskEnabled, let screen = NSScreen.main,
              let left = screen.auxiliaryTopLeftArea, let right = screen.auxiliaryTopRightArea else { return bar.manualNotchWidth }
        return bar.manualNotchWidth > 0 ? CGFloat(bar.manualNotchWidth) : max(0, right.minX - left.maxX)
    }
    private var shelfHeight: CGFloat { bar.notchMaskEnabled ? (bar.notchMaskHeight > 0 ? CGFloat(bar.notchMaskHeight) : max(NSScreen.main?.safeAreaInsets.top ?? 0, 32)) : 0 }
    var body: some View {
        ScrollView(.horizontal, showsIndicators: true) {
            BarView(model: model, notchWidth: notchWidth, topReservedHeight: shelfHeight)
                .frame(width: screenWidth, height: bar.height + bar.outerInset * 2 + shelfHeight)
                .allowsHitTesting(false)
        }
        .frame(height: bar.height + bar.outerInset * 2 + shelfHeight + 12)
        .background(Color(hex: "#202124"))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.primary.opacity(0.1)))
    }
}

private struct BarStylePreview: View {
    @ObservedObject var model: AppModel
    let style: BuiltInBarStyle
    private var preview: BarConfiguration { model.barConfiguration(for: style) }
    var body: some View {
        Button { model.applyBarStyle(style) } label: {
            VStack(alignment: .leading, spacing: 8) {
                GeometryReader { proxy in
                    let sourceWidth: CGFloat = 760
                    let scale = proxy.size.width / sourceWidth
                    ZStack(alignment: .topLeading) {
                        LinearGradient(colors: [Color(hex: preview.palette.muted).opacity(0.3), Color(hex: preview.palette.background).opacity(0.75)], startPoint: .topLeading, endPoint: .bottomTrailing)
                        BarView(model: model, notchWidth: preview.reserveNotchSpace && !preview.notchMaskEnabled ? 122 : 0, topReservedHeight: preview.notchMaskEnabled ? 32 : 0, configurationOverride: preview)
                            .frame(width: sourceWidth, height: preview.height + preview.outerInset * 2 + (preview.notchMaskEnabled ? 32 : 0))
                            .scaleEffect(scale, anchor: .topLeading).allowsHitTesting(false)
                        if preview.reserveNotchSpace && !preview.notchMaskEnabled {
                            RoundedRectangle(cornerRadius: 10).fill(.black).frame(width: 118, height: 34).offset(x: (sourceWidth - 118) / 2, y: -10).scaleEffect(scale, anchor: .topLeading)
                        }
                    }.clipped()
                }
                .frame(height: 58)
                .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                Text(style.rawValue).font(.system(size: 12, weight: .semibold)).foregroundStyle(.primary)
                Text(style.subtitle).font(.caption2).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(10).background(Color.primary.opacity(0.045)).clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.primary.opacity(0.09)))
        }.buttonStyle(.plain).help("Apply \(style.rawValue)")
    }
}

struct BarSettingsView: View {
    @ObservedObject var model: AppModel
    var body: some View {
        SettingsGroup("Current bar · live at actual height") {
            CurrentBarInspector(model: model)
            Text("This is the same renderer and configuration used on the desktop. It is shown at 1:1 point size; scroll horizontally to inspect the complete display-width layout.").font(.caption).foregroundStyle(.secondary)
        }
        SettingsGroup("Style library") {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3), spacing: 10) {
                ForEach(BuiltInBarStyle.allCases) { style in BarStylePreview(model: model, style: style) }
            }
            Divider()
            HStack {
                TextField("Profile name", text: $model.barProfileName).frame(maxWidth: 180)
                Button("Save current bar") { model.saveBarProfile() }.buttonStyle(.borderedProminent)
                if !model.configuration.savedBars.isEmpty {
                    Menu("Saved bars") {
                        ForEach(model.configuration.savedBars) { profile in Button(profile.name) { model.applyBarProfile(profile) } }
                        Divider(); Button("Remove all saved bars", role: .destructive) { model.configuration.savedBars.removeAll() }
                    }
                }
            }
            Label("Every change is saved automatically", systemImage: "checkmark.circle.fill").font(.caption).foregroundStyle(Color(hex: model.configuration.bar.palette.success))
            Text("Preview a style before applying it. Saved named bars preserve every color, icon, widget, transparency, blur, and position.").font(.caption).foregroundStyle(.secondary)
        }
        HStack(alignment: .top, spacing: 16) {
            SettingsGroup("Placement") {
                Toggle("Show desktop bar", isOn: $model.configuration.bar.enabled)
                Picker("Position", selection: $model.configuration.bar.position) { ForEach(BarPosition.allCases, id: \.self) { Text($0.rawValue).tag($0) } }.pickerStyle(.segmented)
                Toggle("Floating bar", isOn: $model.configuration.bar.floating).disabled(model.configuration.bar.connectedPanel)
                Toggle("Connected edge-to-edge panel", isOn: $model.configuration.bar.connectedPanel)
                Text("Connected mode is a layout setting, not a style. It joins the bar into one square-edged surface while preserving the selected palette and widgets.").font(.caption).foregroundStyle(.secondary)
                Toggle("Show on every display", isOn: $model.configuration.bar.showOnAllDisplays)
                Toggle("Black notch shelf", isOn: Binding(get: { model.configuration.bar.notchMaskEnabled }, set: { enabled in
                    model.configuration.bar.notchMaskEnabled = enabled
                    if enabled { model.configuration.bar.position = .top; model.configuration.bar.reserveNotchSpace = false }
                }))
                if model.configuration.bar.notchMaskEnabled {
                    ValueSlider("Shelf height override", value: $model.configuration.bar.notchMaskHeight, range: 0...60, suffix: "pt")
                    Text(model.configuration.bar.notchMaskHeight == 0 ? "Uses the MacBook safe-area height automatically. The shelf is a full-width, square-edged RGB 0,0,0 mask and the bar begins below it." : "The true-black shelf uses the chosen height and the bar begins immediately below it.").font(.caption).foregroundStyle(.secondary)
                }
                Toggle("Keep widgets clear of the notch", isOn: $model.configuration.bar.reserveNotchSpace).disabled(model.configuration.bar.notchMaskEnabled)
                if model.configuration.bar.reserveNotchSpace && !model.configuration.bar.notchMaskEnabled {
                    Toggle("Split bar around notch", isOn: $model.configuration.bar.splitAroundNotch)
                    ValueSlider("Notch width override", value: $model.configuration.bar.manualNotchWidth, range: 0...260, suffix: "pt")
                    Text(model.configuration.bar.splitAroundNotch ? "The left and right bar surfaces stop before the camera area." : "Widgets avoid the camera area while one continuous background runs behind it.").font(.caption).foregroundStyle(.secondary)
                    Text(model.configuration.bar.manualNotchWidth == 0 ? "Auto detects each display. External displays report no notch." : "Manual width replaces safe-area detection on every display.").font(.caption).foregroundStyle(.secondary)
                }
                Divider()
                Toggle("Round bottom display corners", isOn: $model.configuration.bar.roundBottomDisplayCorners)
                if model.configuration.bar.roundBottomDisplayCorners {
                    ValueSlider("Display corner radius", value: $model.configuration.bar.displayCornerRadius, range: 6...48, suffix: "pt")
                    Text("Adds true-black masks to the lower-left and lower-right corners on each active display.").font(.caption).foregroundStyle(.secondary)
                }
            }
            SettingsGroup("Geometry") {
                ValueSlider("Height", value: $model.configuration.bar.height, range: 28...64, suffix: "pt")
                ValueSlider("Corner radius", value: $model.configuration.bar.cornerRadius, range: 0...30, suffix: "pt")
                ValueSlider("Edge inset", value: $model.configuration.bar.horizontalInset, range: 0...30, suffix: "pt")
                ValueSlider("Widget spacing", value: $model.configuration.bar.itemSpacing, range: 0...18, suffix: "pt")
                Toggle("Bar background", isOn: $model.configuration.bar.showBackground)
                Toggle("Blur", isOn: $model.configuration.bar.blurEnabled).disabled(!model.configuration.bar.showBackground)
                if model.configuration.bar.blurEnabled {
                    Picker("Blur material", selection: $model.configuration.bar.blurStyle) { ForEach(BarBlurStyle.allCases) { Text($0.rawValue).tag($0) } }.pickerStyle(.segmented)
                }
                ValueSlider("Transparency", value: Binding(get: { 1 - model.configuration.bar.opacity }, set: { model.configuration.bar.opacity = 1 - $0 }), range: 0...1, suffix: "")
                Text("0% is fully opaque. 100% is fully transparent. Blur uses a stable wallpaper-backed image so Space gestures cannot change its material emphasis or turn it black.").font(.caption).foregroundStyle(.secondary)
                Divider()
                Toggle("Blur sidebars and wallpaper gallery", isOn: $model.configuration.bar.panelBlurEnabled)
                ValueSlider("Panel tint", value: $model.configuration.bar.panelOpacity, range: 0...1, suffix: "")
            }
        }
    }
}

struct ValueSlider: View {
    let name: String; @Binding var value: Double; let range: ClosedRange<Double>; let suffix: String
    init(_ name: String, value: Binding<Double>, range: ClosedRange<Double>, suffix: String) { self.name = name; _value = value; self.range = range; self.suffix = suffix }
    var body: some View {
        VStack(spacing: 5) {
            HStack { Text(name); Spacer(); Text(suffix.isEmpty ? String(format: "%.0f%%", value * 100) : "\(Int(value)) \(suffix)").monospacedDigit().foregroundStyle(.secondary) }
            Slider(value: $value, in: range)
        }
    }
}

struct ThemeSettingsView: View {
    @ObservedObject var model: AppModel
    private let themes: [ThemePalette] = [.sebastian, .trueBlack, .graphite, .paper]
    var body: some View {
        SettingsGroup("Presets") {
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                ForEach(themes) { theme in
                    Button { model.configuration.bar.palette = theme } label: {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack(spacing: 0) { ForEach([theme.background, theme.surface, theme.accent, theme.success], id: \.self) { Color(hex: $0).frame(height: 28) } }.clipShape(RoundedRectangle(cornerRadius: 7))
                            Text(theme.name).fontWeight(.semibold).foregroundStyle(.primary)
                            Text(theme.source).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        }.padding(12).frame(maxWidth: .infinity, alignment: .leading)
                            .background(model.configuration.bar.palette.id == theme.id ? Color.accentColor.opacity(0.1) : .clear)
                            .clipShape(RoundedRectangle(cornerRadius: 10)).overlay(RoundedRectangle(cornerRadius: 10).stroke(model.configuration.bar.palette.id == theme.id ? Color.accentColor : .primary.opacity(0.08)))
                    }.buttonStyle(.plain)
                }
            }
        }
        SettingsGroup("Custom palette") {
            ColorRow("Background", hex: paletteBinding(\.background))
            ColorRow("Raised surface", hex: paletteBinding(\.surface))
            ColorRow("Text", hex: paletteBinding(\.foreground))
            ColorRow("Muted text", hex: paletteBinding(\.muted))
            ColorRow("Accent", hex: paletteBinding(\.accent))
            ColorRow("Success", hex: paletteBinding(\.success))
        }
    }
    private func paletteBinding(_ keyPath: WritableKeyPath<ThemePalette, String>) -> Binding<String> {
        Binding(get: { model.configuration.bar.palette[keyPath: keyPath] }, set: { model.configuration.bar.palette.id = "custom"; model.configuration.bar.palette.name = "Custom"; model.configuration.bar.palette[keyPath: keyPath] = $0 })
    }
}

struct ColorRow: View {
    let name: String; @Binding var hex: String
    init(_ name: String, hex: Binding<String>) { self.name = name; _hex = hex }
    var body: some View {
        HStack { Text(name); Spacer(); Text(hex).font(.system(.caption, design: .monospaced)).foregroundStyle(.secondary); ColorPicker("", selection: Binding(get: { Color(hex: hex) }, set: { hex = NSColor($0).hexString })).labelsHidden() }
    }
}

struct ModuleSettingsView: View {
    @ObservedObject var model: AppModel
    var body: some View {
        HStack {
            Text("Drag widgets on the exact bar above, or use the detailed controls below.").font(.caption).foregroundStyle(.secondary)
            Spacer()
            Menu("Add widget", systemImage: "plus") {
                ForEach(WidgetKind.allCases.filter { $0 != .spacer }) { kind in Button(kind.rawValue) { add(kind) } }
                Divider()
                Button("Flexible space") { add(.spacer) }
            }
        }
        SettingsGroup("Widget layout") {
            if model.configuration.bar.widgets.isEmpty { Text("Add a widget to begin.").foregroundStyle(.secondary) }
            ForEach(Array(model.configuration.bar.widgets.indices), id: \.self) { index in
                WidgetEditor(model: model, index: index, selected: model.configuration.bar.widgets[index].id == model.selectedEditorWidget)
                if index < model.configuration.bar.widgets.count - 1 { Divider() }
            }
        }
        SettingsGroup("Desktop buttons") {
            Stepper("Number of desktops: \(model.configuration.bar.workspaceCount)", value: $model.configuration.bar.workspaceCount, in: 1...9)
            Text("Desktop buttons send macOS Control+Number. Enable matching shortcuts in System Settings, Keyboard, Keyboard Shortcuts, Mission Control.").font(.caption).foregroundStyle(.secondary)
            Button("Request accessibility permission") { WorkspaceController.requestAccessibility() }
        }
    }
    private func add(_ kind: WidgetKind) {
        model.configuration.bar.widgets.append(WidgetConfiguration(kind: kind, name: kind.rawValue, placement: .trailing, icon: kind.defaultIcon, style: kind == .customScript ? .pill : .plain))
    }
}

private struct WidgetEditor: View {
    @ObservedObject var model: AppModel
    let index: Int
    let selected: Bool
    private let icons = ["macwindow", "clock", "calendar", "wifi", "antenna.radiowaves.left.and.right", "battery.75percent", "bolt.fill", "speaker.wave.2", "music.note", "cpu", "memorychip", "terminal", "folder", "photo", "cloud.sun", "bell", "lock", "shield", "slider.horizontal.3", "circle.fill"]
    private var widget: WidgetConfiguration { model.configuration.bar.widgets[index] }

    var body: some View {
        DisclosureGroup {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Picker("Position", selection: $model.configuration.bar.widgets[index].placement) { ForEach(WidgetPlacement.allCases) { Text($0.shortName).tag($0) } }
                    Picker("Look", selection: $model.configuration.bar.widgets[index].style) { ForEach(WidgetStyle.allCases) { Text($0.rawValue).tag($0) } }
                }
                HStack {
                    TextField("Widget name", text: $model.configuration.bar.widgets[index].name)
                    TextField("SF Symbol, text:☁︎, or image path", text: $model.configuration.bar.widgets[index].icon).font(.system(.body, design: .monospaced))
                    Menu {
                        ForEach(icons, id: \.self) { icon in Button { model.configuration.bar.widgets[index].icon = icon } label: { Label(icon, systemImage: icon) } }
                        Divider()
                        ForEach(["", "●", "◆", "☀︎", "☁︎"], id: \.self) { glyph in Button(glyph) { model.configuration.bar.widgets[index].icon = "text:\(glyph)" } }
                        Divider()
                        Button("Choose image…") { chooseImage() }
                    } label: { WidgetIcon(value: widget.icon).frame(width: 24) }
                }
                HStack { Toggle("Icon", isOn: $model.configuration.bar.widgets[index].showIcon); Toggle("Value", isOn: $model.configuration.bar.widgets[index].showLabel); Spacer() }
                HStack {
                    ValueSlider("Type size", value: $model.configuration.bar.widgets[index].fontSize, range: 9...22, suffix: "pt")
                    ValueSlider("Padding", value: $model.configuration.bar.widgets[index].horizontalPadding, range: 0...24, suffix: "pt")
                    ValueSlider("Radius", value: $model.configuration.bar.widgets[index].cornerRadius, range: 0...20, suffix: "pt")
                }
                OptionalColorRow(label: "Widget text", value: $model.configuration.bar.widgets[index].foreground)
                OptionalColorRow(label: "Widget background", value: $model.configuration.bar.widgets[index].background)
                if widget.kind == .customScript {
                    TextField("Shell command that prints a value", text: $model.configuration.bar.widgets[index].script)
                    ValueSlider("Refresh", value: $model.configuration.bar.widgets[index].refreshInterval, range: 2...300, suffix: "sec")
                }
                Picker("When clicked", selection: $model.configuration.bar.widgets[index].clickAction) { ForEach(WidgetClickAction.allCases) { Text($0.rawValue).tag($0) } }
                if widget.clickAction == .shell { TextField("Command to run", text: $model.configuration.bar.widgets[index].clickCommand) }
                HStack {
                    Button("Duplicate") { var copy = widget; copy.id = UUID(); copy.name += " copy"; model.configuration.bar.widgets.insert(copy, at: index + 1) }
                    Spacer()
                    Button("Remove", role: .destructive) { model.configuration.bar.widgets.remove(at: index) }
                }
            }.padding(.top, 10)
        } label: {
            HStack(spacing: 10) {
                Toggle("", isOn: $model.configuration.bar.widgets[index].enabled).labelsHidden()
                WidgetIcon(value: widget.icon).frame(width: 18)
                VStack(alignment: .leading, spacing: 2) { Text(widget.name).fontWeight(.medium); Text(widget.placement.shortName).font(.caption).foregroundStyle(.secondary) }
                Spacer()
                Button { move(-1) } label: { Image(systemName: "arrow.up") }.buttonStyle(.borderless).disabled(index == 0)
                Button { move(1) } label: { Image(systemName: "arrow.down") }.buttonStyle(.borderless).disabled(index >= model.configuration.bar.widgets.count - 1)
            }
        }
        .padding(selected ? 8 : 0)
        .background(selected ? Color.accentColor.opacity(0.1) : .clear)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .animation(.easeOut(duration: NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? 0 : 0.18), value: selected)
    }
    private func move(_ offset: Int) { model.configuration.bar.widgets.swapAt(index, index + offset) }
    private func chooseImage() {
        let panel = NSOpenPanel(); panel.canChooseDirectories = false; panel.allowedContentTypes = [.image]
        if panel.runModal() == .OK, let path = panel.url?.path { model.configuration.bar.widgets[index].icon = path }
    }
}

struct TilingSettingsView: View {
    @ObservedObject var model: AppModel
    @ObservedObject private var tiling: TilingService
    init(model: AppModel) { self.model = model; self.tiling = model.tiling }
    var body: some View {
        SettingsGroup("Hyprland window manager") {
            Toggle("Enable automatic tiling", isOn: Binding(get: { model.configuration.tiling.enabled }, set: { enabled in
                model.configuration.tiling.enabled = enabled; model.configuration.tiling.autoTile = enabled
            }))
            Text("When enabled, every new standard window is tiled immediately. Closing, minimizing, launching, or changing displays automatically reflows the current Mission Control desktop.").font(.caption).foregroundStyle(.secondary)
            Picker("Layout", selection: $model.configuration.tiling.layout) { ForEach(TilingLayout.allCases) { Text($0.rawValue).tag($0) } }
            HStack {
                Button("Tile now") { model.tiling.tileNow() }.buttonStyle(.borderedProminent).disabled(!model.configuration.tiling.enabled)
                Button("Focus next") { model.tiling.focusNext() }.disabled(!model.configuration.tiling.enabled)
                if !tiling.hasAccessibility { Button("Grant Accessibility…") { model.tiling.requestAccessibility() } }
                Spacer(); Text("\(tiling.managedWindowCount) managed · \(tiling.status)").foregroundStyle(.secondary)
            }
        }
        SettingsGroup("Layout geometry") {
            ValueSlider("Inner gaps", value: $model.configuration.tiling.innerGap, range: 0...40, suffix: "pt")
            ValueSlider("Outer gaps", value: $model.configuration.tiling.outerGap, range: 0...50, suffix: "pt")
            if model.configuration.tiling.layout == .masterStack { ValueSlider("Master width", value: $model.configuration.tiling.masterRatio, range: 0.35...0.75, suffix: "") }
        }
        SettingsGroup("Floating exceptions") {
            Text("One bundle identifier per line. Matching applications remain floating.").font(.caption).foregroundStyle(.secondary)
            TextEditor(text: Binding(get: { model.configuration.tiling.ignoredBundleIDs.joined(separator: "\n") }, set: { model.configuration.tiling.ignoredBundleIDs = $0.components(separatedBy: .newlines).filter { !$0.isEmpty } })).font(.system(.body, design: .monospaced)).frame(minHeight: 110)
        }
        Text("Hyprland dwindle recursively splits the remaining leaf along its longest axis. Waycode manages only visible, resizable standard windows on the current Mission Control desktop; dialogs, sheets, fullscreen windows, other Spaces, and excluded apps remain floating. macOS Accessibility permission is required.").font(.caption).foregroundStyle(.secondary)
    }
}

private struct OptionalColorRow: View {
    let label: String; @Binding var value: String?
    var body: some View {
        HStack {
            Toggle("Custom \(label.lowercased())", isOn: Binding(get: { value != nil }, set: { value = $0 ? "#CBC4CB" : nil }))
            Spacer()
            if let current = value {
                Text(current).font(.system(.caption, design: .monospaced)).foregroundStyle(.secondary)
                ColorPicker("", selection: Binding(get: { Color(hex: current) }, set: { value = NSColor($0).hexString })).labelsHidden()
            }
        }
    }
}
