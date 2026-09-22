import SwiftUI

private struct SidebarShell<Content: View>: View {
    let appearance: BarConfiguration
    let close: () -> Void
    @ViewBuilder let content: Content
    private var palette: ThemePalette { appearance.palette }
    init(appearance: BarConfiguration, close: @escaping () -> Void, @ViewBuilder content: () -> Content) { self.appearance = appearance; self.close = close; self.content = content() }
    var body: some View {
        ZStack {
            if appearance.panelBlurEnabled { RoundedRectangle(cornerRadius: 18, style: .continuous).fill(.regularMaterial) }
            RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Color(hex: palette.background).opacity(appearance.panelOpacity))
                .overlay(RoundedRectangle(cornerRadius: 18).stroke(Color(hex: palette.muted).opacity(0.35)))
            content.padding(10)
        }
        .foregroundStyle(Color(hex: palette.foreground))
        .overlay(alignment: .topTrailing) { Button(action: close) { Image(systemName: "xmark").frame(width: 26, height: 26) }.buttonStyle(.plain).padding(13) }
        .padding(8)
    }
}

struct LeftSidebarView: View {
    @ObservedObject var model: AppModel
    @ObservedObject private var gemini: GeminiService
    let close: () -> Void
    private var palette: ThemePalette { model.configuration.bar.palette }

    init(model: AppModel, close: @escaping () -> Void) {
        self.model = model; self.gemini = model.gemini; self.close = close
    }

    var body: some View {
        SidebarShell(appearance: model.configuration.bar, close: close) {
            VStack(spacing: 12) {
                HStack(spacing: 10) {
                    ZStack { Circle().fill(Color(hex: palette.accent)); Image(systemName: "sparkles").foregroundStyle(Color(hex: palette.background)) }.frame(width: 34, height: 34)
                    VStack(alignment: .leading, spacing: 1) { Text("Gemini").font(.system(size: 16, weight: .semibold, design: .rounded)); Text("Waycode assistant").font(.caption).foregroundStyle(Color(hex: palette.muted)) }
                    Spacer()
                    Circle().fill(gemini.hasAPIKey ? Color(hex: palette.success) : Color(hex: palette.muted)).frame(width: 7, height: 7)
                }.padding(.trailing, 34)

                if !gemini.hasAPIKey { keySetup }
                else { conversation }
            }
        }
    }

    private var keySetup: some View {
        VStack(alignment: .leading, spacing: 13) {
            Spacer()
            Image(systemName: "key.fill").font(.system(size: 28)).foregroundStyle(Color(hex: palette.accent))
            Text("Connect Gemini").font(.title2.weight(.semibold))
            Text("Paste a Google AI Studio API key. It is stored only in your macOS Keychain and is never written to Waycode’s config or repository.").foregroundStyle(Color(hex: palette.muted))
            SecureField("Gemini API key", text: $gemini.apiKeyDraft).textFieldStyle(.plain).onSubmit { gemini.saveAPIKey() }
                .padding(12).background(Color(hex: palette.surface)).clipShape(RoundedRectangle(cornerRadius: 12))
            Button("Save securely") { gemini.saveAPIKey() }.buttonStyle(.borderedProminent).tint(Color(hex: palette.accent))
            if !gemini.errorMessage.isEmpty { Text(gemini.errorMessage).font(.caption).foregroundStyle(.red) }
            Spacer()
        }.padding(18).background(Color(hex: palette.surface).opacity(0.45)).clipShape(RoundedRectangle(cornerRadius: 17))
    }

    private var conversation: some View {
        VStack(spacing: 10) {
            ScrollViewReader { proxy in
                ScrollView(showsIndicators: false) {
                    LazyVStack(spacing: 10) {
                        ForEach(gemini.messages) { message in
                            HStack {
                                if message.role == "user" { Spacer(minLength: 42) }
                                Text(message.text).textSelection(.enabled).padding(.horizontal, 12).padding(.vertical, 10)
                                    .background(Color(hex: message.role == "user" ? palette.accent : palette.surface))
                                    .foregroundStyle(Color(hex: message.role == "user" ? palette.background : palette.foreground))
                                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                                if message.role != "user" { Spacer(minLength: 42) }
                            }.id(message.id)
                        }
                        if gemini.isLoading { HStack { ProgressView().controlSize(.small); Text("Thinking…").font(.caption).foregroundStyle(Color(hex: palette.muted)); Spacer() } }
                    }.padding(3)
                }.onChange(of: gemini.messages.count) { _ in if let id = gemini.messages.last?.id { proxy.scrollTo(id, anchor: .bottom) } }
            }
            if !gemini.errorMessage.isEmpty { Text(gemini.errorMessage).font(.caption).foregroundStyle(.red).frame(maxWidth: .infinity, alignment: .leading) }
            HStack(spacing: 8) {
                TextField("Message Gemini", text: $gemini.draft, axis: .vertical).textFieldStyle(.plain).lineLimit(1...5).onSubmit { gemini.send() }
                Button { gemini.send() } label: { Image(systemName: "arrow.up").fontWeight(.bold).frame(width: 30, height: 30).background(Color(hex: palette.accent)).foregroundStyle(Color(hex: palette.background)).clipShape(Circle()) }.buttonStyle(.plain).disabled(gemini.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || gemini.isLoading)
            }.padding(10).background(Color(hex: palette.surface)).clipShape(RoundedRectangle(cornerRadius: 15))
            HStack { Button("Remove API key", role: .destructive) { gemini.removeAPIKey() }.buttonStyle(.plain).font(.caption); Spacer(); Text("⌥A").font(.caption.monospaced()).foregroundStyle(Color(hex: palette.muted)) }
        }
    }
}

struct RightSidebarView: View {
    @ObservedObject var model: AppModel
    @ObservedObject private var system: SystemMonitor
    @ObservedObject private var controls: SystemControlService
    let close: () -> Void
    private var palette: ThemePalette { model.configuration.bar.palette }
    init(model: AppModel, close: @escaping () -> Void) { self.model = model; self.system = model.system; self.controls = model.controls; self.close = close }

    var body: some View {
        SidebarShell(appearance: model.configuration.bar, close: close) {
            if model.rightSidebarDetail.isEmpty {
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 11) { systemRow; quickToggles; resources; calendar; todos }.padding(.trailing, 1)
                }.transition(.move(edge: .leading).combined(with: .opacity))
            } else {
                VStack(spacing: 10) {
                    HStack { Button { model.rightSidebarDetail = "" } label: { Label("Controls", systemImage: "chevron.left") }.buttonStyle(.plain); Spacer(); Text(model.rightSidebarDetail).font(.headline); Spacer().frame(width: 55) }
                    detailView
                    if !controls.operationMessage.isEmpty { Text(controls.operationMessage).font(.caption).foregroundStyle(Color(hex: palette.muted)).lineLimit(2) }
                }.padding(6).transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .animation(.easeOut(duration: NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? 0 : 0.2), value: model.rightSidebarDetail)
    }

    private var systemRow: some View {
        HStack {
            Label("Up \(system.uptime)", systemImage: "chevron.left.forwardslash.chevron.right").padding(.horizontal, 12).frame(height: 38).background(Color(hex: palette.surface)).clipShape(Capsule())
            Spacer()
            HStack(spacing: 2) {
                iconButton("arrow.clockwise") { system.refresh() }
                iconButton("gearshape") { NotificationCenter.default.post(name: .waycodeShowSettings, object: nil); close() }
                iconButton("power") { model.openSystemSettings("preference.security") }
            }.padding(4).background(Color(hex: palette.surface)).clipShape(Capsule())
        }.padding(.trailing, 34)
    }
    private var quickToggles: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 7) {
            quick("Wi-Fi", icon: "wifi", subtitle: controls.connectedSSID) { model.rightSidebarDetail = "Wi-Fi"; controls.requestWiFiAccessAndScan() }
            quick("Bluetooth", icon: "bluetooth", subtitle: "Devices") { model.openSystemSettings("Bluetooth") }
            quick("Dark mode", icon: "moon.fill", subtitle: "Appearance") { model.toggleAppearance() }
            quick("Battery", icon: controls.lowPowerMode ? "battery.25percent" : "battery.75percent", subtitle: controls.lowPowerMode ? "Low Power Mode" : controls.batteryPercent) { model.rightSidebarDetail = "Battery"; controls.refreshPowerState() }
        }
    }
    private var resources: some View {
        HStack(spacing: 8) {
            resource("CPU", value: system.cpu, icon: "cpu")
            resource("Memory", value: system.memory, icon: "memorychip")
            Button { model.rightSidebarDetail = "Battery"; controls.refreshPowerState() } label: { resource("Battery", value: system.battery, icon: "battery.75percent") }.buttonStyle(.plain)
        }.padding(10).background(Color(hex: palette.surface)).clipShape(RoundedRectangle(cornerRadius: 17))
    }
    private var calendar: some View {
        DatePicker("", selection: .constant(Date()), displayedComponents: [.date]).datePickerStyle(.graphical).labelsHidden()
            .padding(8).background(Color(hex: palette.surface)).clipShape(RoundedRectangle(cornerRadius: 17))
    }
    private var todos: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Tasks").font(.headline)
            ForEach(Array(model.configuration.todos.enumerated()), id: \.offset) { index, todo in
                HStack { Image(systemName: "circle"); Text(todo); Spacer(); Button { model.configuration.todos.remove(at: index) } label: { Image(systemName: "checkmark") }.buttonStyle(.plain) }
            }
            HStack { TextField("Add a task", text: $model.todoDraft).textFieldStyle(.plain).onSubmit { model.addTodo() }; Button { model.addTodo() } label: { Image(systemName: "plus.circle.fill") }.buttonStyle(.plain) }
                .padding(10).background(Color(hex: palette.background)).clipShape(RoundedRectangle(cornerRadius: 12))
        }.padding(14).background(Color(hex: palette.surface)).clipShape(RoundedRectangle(cornerRadius: 17))
    }
    @ViewBuilder private var detailView: some View {
        switch model.rightSidebarDetail {
        case "Wi-Fi": wifiDetail
        case "Sound": soundDetail
        case "Battery": batteryDetail
        default: EmptyView()
        }
    }
    private var wifiDetail: some View {
        VStack(spacing: 10) {
            HStack { Toggle("Wi-Fi", isOn: Binding(get: { controls.wifiEnabled }, set: { controls.setWiFiEnabled($0) })); Spacer(); Button { controls.scanWiFi() } label: { if controls.scanningWiFi { ProgressView().controlSize(.small) } else { Image(systemName: "arrow.clockwise") } }.buttonStyle(.plain) }
            if controls.connectedSSID != "Not connected" { HStack { Label(controls.connectedSSID, systemImage: "checkmark.circle.fill"); Spacer(); Button("Disconnect") { controls.disconnectWiFi() } }.padding(10).background(Color(hex: palette.surface)).clipShape(RoundedRectangle(cornerRadius: 12)) }
            ScrollView {
                LazyVStack(spacing: 5) {
                    ForEach(controls.wifiNetworks) { network in
                        VStack(spacing: 7) {
                            Button {
                                model.selectedWiFiID = network.id
                                model.wifiPassword = ""
                                if !network.secure { controls.connect(to: network, password: "") }
                            } label: {
                                HStack { Image(systemName: signalIcon(network.signal)); Text(network.ssid).lineLimit(1); Spacer(); if network.secure { Image(systemName: "lock.fill").font(.caption) }; Text("\(network.signal) dBm").font(.caption).foregroundStyle(Color(hex: palette.muted)) }
                            }.buttonStyle(.plain)
                            if model.selectedWiFiID == network.id && network.secure {
                                HStack { SecureField("Password", text: $model.wifiPassword).textFieldStyle(.plain).onSubmit { controls.connect(to: network, password: model.wifiPassword) }; Button("Connect") { controls.connect(to: network, password: model.wifiPassword) }.buttonStyle(.borderedProminent) }
                                    .padding(9).background(Color(hex: palette.background)).clipShape(RoundedRectangle(cornerRadius: 10))
                            }
                        }.padding(10).background(Color(hex: palette.surface)).clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                }
            }
        }
    }
    private var soundDetail: some View {
        VStack(spacing: 10) {
            HStack { Image(systemName: "speaker.wave.2.fill"); Slider(value: Binding(get: { controls.outputVolume }, set: { controls.setOutputVolume($0) }), in: 0...100); Text("\(Int(controls.outputVolume))").monospacedDigit().frame(width: 30) }.padding(12).background(Color(hex: palette.surface)).clipShape(RoundedRectangle(cornerRadius: 14))
            HStack { Button("Mute") { controls.setMuted(true) }; Button("Unmute") { controls.setMuted(false) }; Spacer(); Button { controls.refreshAudioDevices() } label: { Image(systemName: "arrow.clockwise") } }.buttonStyle(.bordered)
            ScrollView {
                LazyVStack(spacing: 5) {
                    ForEach(controls.audioDevices) { device in
                        Button { controls.selectAudioDevice(device.id) } label: { HStack { Image(systemName: device.id == controls.defaultAudioDevice ? "checkmark.circle.fill" : "circle"); Text(device.name); Spacer() }.padding(12).background(Color(hex: palette.surface)).clipShape(RoundedRectangle(cornerRadius: 12)) }.buttonStyle(.plain)
                    }
                }
            }
        }
    }
    private var batteryDetail: some View {
        VStack(spacing: 14) {
            Image(systemName: "battery.75percent").font(.system(size: 46)).foregroundStyle(Color(hex: palette.accent))
            Text(controls.batteryPercent).font(.system(size: 34, weight: .semibold, design: .rounded))
            Toggle("Low Power Mode", isOn: Binding(get: { controls.lowPowerMode }, set: { controls.setLowPowerMode($0) }))
                .padding(14).background(Color(hex: palette.surface)).clipShape(RoundedRectangle(cornerRadius: 14))
            Text("macOS requires administrator approval when changing Low Power Mode. Waycode uses pmset and shows the standard system authorization prompt.").font(.caption).foregroundStyle(Color(hex: palette.muted)).multilineTextAlignment(.center)
            Button("Open Battery Settings") { model.openSystemSettings("Battery-Settings.extension") }.buttonStyle(.bordered)
            Spacer()
        }.padding(.top, 30)
    }
    private func signalIcon(_ value: Int) -> String { value > -55 ? "wifi" : value > -72 ? "wifi" : "wifi.exclamationmark" }
    private func iconButton(_ icon: String, action: @escaping () -> Void) -> some View { Button(action: action) { Image(systemName: icon).frame(width: 28, height: 28) }.buttonStyle(.plain) }
    private func quick(_ title: String, icon: String, subtitle: String, action: @escaping () -> Void) -> some View {
        Button(action: action) { HStack { Image(systemName: icon).font(.title3).foregroundStyle(title == "Battery" && controls.lowPowerMode ? Color.yellow : Color(hex: palette.foreground)); VStack(alignment: .leading) { Text(title).fontWeight(.semibold); Text(subtitle).font(.caption).foregroundStyle(Color(hex: palette.muted)).lineLimit(1) }; Spacer() }.padding(12).background(Color(hex: palette.surface)).clipShape(RoundedRectangle(cornerRadius: 15)) }.buttonStyle(.plain)
    }
    private func resource(_ title: String, value: String, icon: String) -> some View { VStack(spacing: 4) { Image(systemName: icon); Text(value).fontWeight(.semibold); Text(title).font(.caption).foregroundStyle(Color(hex: palette.muted)) }.frame(maxWidth: .infinity) }
}
