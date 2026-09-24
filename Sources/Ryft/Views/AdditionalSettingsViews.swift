import SwiftUI
import AppKit
import UniformTypeIdentifiers
import ApplicationServices
import CoreLocation

struct AssistantSettingsView: View {
    @ObservedObject var model: AppModel
    @ObservedObject private var gemini: GeminiService

    init(model: AppModel) {
        self.model = model
        gemini = model.gemini
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            SettingsGroup("Gemini connection") {
                HStack(spacing: 10) {
                    Circle().fill(gemini.hasAPIKey ? Color(hex: model.configuration.bar.palette.success) : Color.red).frame(width: 8, height: 8)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(gemini.hasAPIKey ? "Connected securely" : "Credential unavailable").fontWeight(.semibold)
                        Text("Stored in macOS Keychain and cached by Ryft. It is never written to profiles, chat history, screenshots, or Git.").font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    if gemini.hasAPIKey { Button("Remove", role: .destructive) { gemini.removeAPIKey() }.buttonStyle(.bordered) }
                }
                SecureField(gemini.hasAPIKey ? "Paste a replacement key" : "Paste Gemini API key", text: $gemini.apiKeyDraft)
                    .textFieldStyle(.roundedBorder).onSubmit { gemini.saveAPIKey() }
                HStack {
                    Button(gemini.hasAPIKey ? "Replace key" : "Save key") { gemini.saveAPIKey() }.buttonStyle(.borderedProminent)
                        .disabled(gemini.apiKeyDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    Button("Open Google AI Studio") { gemini.openAIStudio() }.buttonStyle(.bordered)
                }
            }

            SettingsGroup("Command+M answers") {
                instructionRow("1", "Select text first", "When text is highlighted in the frontmost app, Command+M sends only that text to Gemini. No screenshot is captured.")
                instructionRow("2", "Otherwise use the visible window", "Without a selection, Ryft captures the focused window in memory and asks Gemini to answer the visible question.")
                instructionRow("3", "Copy longer answers", "Click the answer in the top-left bar to copy it. Long answers scroll across twice before disappearing.")
                Button { model.answerQuestionOnScreen() } label: { Label("Test Command+M", systemImage: "sparkles") }.buttonStyle(.borderedProminent)
                Text("Single choices remain visible for 3 seconds. Written answers remain until their complete marquee has passed twice. Screen capture occurs only after Command+M and is never saved.").font(.caption).foregroundStyle(.secondary)
            }

            SettingsGroup("Automatic model routing") {
                Text("Ryft tries the highest-ranked healthy model, falls through the list on quota, timeout, or service errors, and automatically retries better models after their cooldown expires.").font(.callout).foregroundStyle(.secondary)
                ForEach(gemini.modelUsages) { usage in
                    HStack {
                        Circle().fill(usage.id == gemini.currentModelID ? Color(hex: model.configuration.bar.palette.success) : Color.secondary.opacity(0.35)).frame(width: 6, height: 6)
                        Text(usage.name)
                        Spacer()
                        Text("\(usage.remaining) remaining").font(.system(.caption, design: .monospaced)).foregroundStyle(.secondary)
                    }
                }
            }

            SettingsGroup("Assistant sidebar") {
                Label("Open Gemini from the sparkle widget in the desktop bar.", systemImage: "sparkle")
                Label("Chats are stored locally and responses can be selected or copied.", systemImage: "doc.on.doc")
                Label("Slash commands, new chat, stop, copy, key controls, token counts, and model usage are available in the panel.", systemImage: "sidebar.left")
                HStack {
                    Button("Open Gemini") { NotificationCenter.default.post(name: .ryftToggleLeftSidebar, object: nil) }.buttonStyle(.borderedProminent)
                    Button("New conversation") { gemini.newConversation() }.buttonStyle(.bordered)
                    Button("Copy last answer") { gemini.copyLastResponse() }.buttonStyle(.bordered)
                }
            }
        }
        .onAppear { gemini.refreshCredentialState() }
    }

    private func instructionRow(_ number: String, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: 11) {
            Text(number).font(.caption.bold()).frame(width: 22, height: 22).background(Color(hex: model.configuration.bar.palette.accent).opacity(0.2)).clipShape(Circle())
            VStack(alignment: .leading, spacing: 2) { Text(title).fontWeight(.semibold); Text(detail).font(.caption).foregroundStyle(.secondary) }
        }
    }
}

struct ShortcutSettingsView: View {
    @ObservedObject var model: AppModel
    private let keys = GlobalHotkeyManager.keyCodes.keys.sorted()
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
        SettingsGroup("Built-in shortcuts") {
            fixedShortcut("⌘M", "Secret AI answer", "Uses highlighted question text when available; otherwise reads the focused window. Click a written answer to copy it.")
            Divider()
            HStack(spacing: 12) {
                Text("⌘↩").font(.system(.body, design: .monospaced).weight(.semibold)).frame(width: 42)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Open or control Termatica").fontWeight(.semibold)
                    Text(TermaticaIntegrationService.isInstalled ? "Launches Termatica. If it is already visible on this desktop, runs its configured Command+T action; otherwise opens a new window here." : "Install Termatica in Applications to enable this shortcut.").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Toggle("", isOn: $model.configuration.termaticaShortcutEnabled).labelsHidden().disabled(!TermaticaIntegrationService.isInstalled)
            }
            .opacity(TermaticaIntegrationService.isInstalled ? 1 : 0.42)
            Text("Termatica keeps using your current config.json profile exactly as configured. Ryft does not copy, rewrite, or merge its terminal settings. Command+M and Command+Enter are protected from accidental deletion.").font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
        }
        SettingsGroup("Editable shortcuts") {
            ForEach(Array(model.configuration.shortcuts.indices), id: \.self) { index in
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 10) {
                        Picker("Action", selection: $model.configuration.shortcuts[index].action) { ForEach(ShortcutAction.allCases.filter { $0 != .wallpaper && $0 != .randomWallpaper && $0 != .screenAnswer && $0 != .termatica && $0 != .leftSidebar && $0 != .rightSidebar }) { Text($0.rawValue).tag($0) } }.labelsHidden().frame(width: 170)
                        modifier("⌃", value: $model.configuration.shortcuts[index].control)
                        modifier("⌥", value: $model.configuration.shortcuts[index].option)
                        modifier("⇧", value: $model.configuration.shortcuts[index].shift)
                        modifier("⌘", value: $model.configuration.shortcuts[index].command)
                        Picker("Key", selection: $model.configuration.shortcuts[index].key) { ForEach(keys, id: \.self) { Text($0.uppercased()).tag($0) } }.labelsHidden().frame(width: 62)
                        Text(model.configuration.shortcuts[index].display).font(.system(.body, design: .monospaced)).frame(width: 70)
                        Button { test(model.configuration.shortcuts[index]) } label: { Image(systemName: "play.fill") }.buttonStyle(.borderless).help("Test action")
                        Button(role: .destructive) { model.configuration.shortcuts.remove(at: index) } label: { Image(systemName: "trash") }.buttonStyle(.borderless)
                    }
                    if model.configuration.shortcuts[index].action == .openApplication {
                        HStack { TextField("Application path", text: targetBinding(index)); Button("Choose App…") { chooseApplication(index) } }
                    } else if model.configuration.shortcuts[index].action == .runCommand {
                        TextField("Shell command", text: targetBinding(index)).font(.system(.body, design: .monospaced))
                    }
                }.padding(.vertical, 4)
                if index < model.configuration.shortcuts.count - 1 { Divider() }
            }
            HStack {
                Button { model.configuration.shortcuts.append(ShortcutConfiguration(action: .toggleBar, key: "b")) } label: { Label("Add keybind", systemImage: "plus") }
                Button { model.configuration.shortcuts.append(ShortcutConfiguration(action: .openFinder, key: "e", option: false, command: true)) } label: { Label("Add ⌘E Finder", systemImage: "folder") }
            }
            Text("Shortcuts are re-registered immediately and work from every app. Keep at least one modifier selected. If two entries use the same combination, macOS keeps the first one.").font(.caption).foregroundStyle(.secondary)
        }
        }
    }
    private func fixedShortcut(_ keys: String, _ title: String, _ detail: String) -> some View {
        HStack(spacing: 12) {
            Text(keys).font(.system(.body, design: .monospaced).weight(.semibold)).frame(width: 42)
            VStack(alignment: .leading, spacing: 2) { Text(title).fontWeight(.semibold); Text(detail).font(.caption).foregroundStyle(.secondary) }
            Spacer()
        }
    }
    private func modifier(_ label: String, value: Binding<Bool>) -> some View {
        Toggle(label, isOn: value).toggleStyle(.button).buttonStyle(.bordered).help("Toggle \(label) modifier")
    }
    private func targetBinding(_ index: Int) -> Binding<String> {
        Binding(get: { model.configuration.shortcuts[index].target ?? "" }, set: { model.configuration.shortcuts[index].target = $0 })
    }
    private func chooseApplication(_ index: Int) {
        let panel = NSOpenPanel(); panel.allowedContentTypes = [.application]; panel.directoryURL = URL(fileURLWithPath: "/Applications"); panel.canChooseDirectories = false
        if panel.runModal() == .OK { model.configuration.shortcuts[index].target = panel.url?.path }
    }
    private func test(_ shortcut: ShortcutConfiguration) {
        switch shortcut.action {
        case .wallpaper: NotificationCenter.default.post(name: .ryftShowWallpapers, object: nil)
        case .toggleBar: model.configuration.bar.enabled.toggle()
        case .settings: NotificationCenter.default.post(name: .ryftShowSettings, object: nil)
        case .randomWallpaper: model.randomWallpaper()
        case .openFinder: NSWorkspace.shared.openApplication(at: URL(fileURLWithPath: "/System/Library/CoreServices/Finder.app"), configuration: .init())
        case .openApplication: if let path = shortcut.target { NSWorkspace.shared.open(URL(fileURLWithPath: path)) }
        case .runCommand:
            if let command = shortcut.target, !command.isEmpty { let process = Process(); process.executableURL = URL(fileURLWithPath: "/bin/zsh"); process.arguments = ["-lc", command]; try? process.run() }
        case .leftSidebar: NotificationCenter.default.post(name: .ryftToggleLeftSidebar, object: nil)
        case .rightSidebar: NotificationCenter.default.post(name: .ryftToggleRightSidebar, object: nil)
        case .screenAnswer: model.answerQuestionOnScreen()
        case .termatica: TermaticaIntegrationService.openOrControl()
        case .quitFrontmost: _ = NSWorkspace.shared.frontmostApplication?.terminate()
        }
    }
}

struct WallpaperGalleryView: View {
    @ObservedObject var model: AppModel
    let standalone: Bool
    private var palette: ThemePalette { model.configuration.bar.palette }
    private var library: [URL] { standalone ? model.wallpapers.filter(model.isFavorite) : model.wallpapers }
    private var categories: [String] { ["All"] + Array(Set(library.map { $0.deletingLastPathComponent().lastPathComponent }).subtracting(["All", "assets"])).sorted() }
    private var filtered: [URL] {
        let categorized = model.wallpaperCategory == "All" ? library : library.filter { $0.deletingLastPathComponent().lastPathComponent == model.wallpaperCategory }
        let searched = model.wallpaperSearch.isEmpty ? categorized : categorized.filter { $0.lastPathComponent.localizedCaseInsensitiveContains(model.wallpaperSearch) }
        return !standalone && model.wallpaperViewMode == 2 ? searched.filter(model.isFavorite) : searched
    }

    var body: some View {
        VStack(spacing: 12) {
            toolbar
            if model.wallpaperViewMode != 0 { categoryBar }
            Group {
                if !standalone && model.wallpaperViewMode == 0 { homeView }
                else if filtered.isEmpty { emptyView }
                else if model.wallpaperGridMode { gridView }
                else { carouselView }
            }.padding(6).background(Color(hex: palette.surface).opacity(0.34)).clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
        .padding(14)
        .background(LinearGradient(colors: [Color(hex: palette.background), Color(hex: palette.surface).opacity(0.72)], startPoint: .topLeading, endPoint: .bottomTrailing))
        .foregroundStyle(Color(hex: palette.foreground))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(Color(hex: palette.muted).opacity(0.3)))
        .padding(standalone ? 8 : 0)
        .focusable()
        .onMoveCommand { direction in moveSelection(direction) }
        .onAppear {
            if !standalone { model.wallpaperViewMode = 1 }
            model.wallpaperCategory = "All"
            model.wallpaperSelectionIndex = 0
        }
    }

    private var toolbar: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 1) {
                Text("RYFT").font(.caption2.weight(.bold)).tracking(2).foregroundStyle(Color(hex: palette.accent))
                Text("Wallpaper library").font(.title3.weight(.semibold))
            }.frame(width: 170, alignment: .leading)
            if !standalone { toolbarButton("house.fill", selected: model.wallpaperViewMode == 0) { model.wallpaperViewMode = 0 } }
            HStack(spacing: 8) { Image(systemName: "magnifyingglass").foregroundStyle(Color(hex: palette.muted)); TextField("Search the library", text: $model.wallpaperSearch).textFieldStyle(.plain); if !model.wallpaperSearch.isEmpty { Button { model.wallpaperSearch = "" } label: { Image(systemName: "xmark.circle.fill") }.buttonStyle(SettingsHoverButtonStyle()).foregroundStyle(Color(hex: palette.muted)) } }
                .padding(.horizontal, 12).frame(maxWidth: .infinity).frame(height: 40).background(Color(hex: palette.surface)).clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
            toolbarButton(model.wallpaperGridMode ? "rectangle.split.3x3" : "rectangle.split.3x1", selected: model.wallpaperGridMode) { model.wallpaperGridMode.toggle(); model.wallpaperViewMode = 1 }
            if !standalone { toolbarButton(model.wallpaperViewMode == 2 ? "heart.fill" : "heart", selected: model.wallpaperViewMode == 2) { model.wallpaperViewMode = model.wallpaperViewMode == 2 ? 1 : 2 } }
            Spacer()
            Menu {
                if !standalone {
                    Button("Add folder") { model.addWallpaperFolder() }
                    Button("Add images") { model.addWallpaperFiles() }
                    Button(model.installingWallpaperArchive ? "Installing archive…" : "Install GitHub wallpaper collection") { model.installWallpaperArchive() }.disabled(model.installingWallpaperArchive)
                    Divider()
                }
                Button("Refresh") { model.refreshWallpapers() }
                Divider()
                Button { model.configuration.adaptColorsToWallpaper.toggle() } label: { Label("Adapt bar colors to wallpaper", systemImage: model.configuration.adaptColorsToWallpaper ? "checkmark" : "circle") }
            } label: { Image(systemName: "plus").frame(width: 28, height: 28) }
            if model.installingWallpaperArchive { ProgressView().controlSize(.small) }
            Button { applySelected() } label: { Label("Apply", systemImage: "checkmark").font(.caption.weight(.semibold)).padding(.horizontal, 12).frame(height: 38).background(Color(hex: palette.accent)).foregroundStyle(Color(hex: palette.background)).clipShape(RoundedRectangle(cornerRadius: 12)) }.buttonStyle(SettingsHoverButtonStyle()).keyboardShortcut(.return, modifiers: []).help("Apply selected wallpaper")
            toolbarButton("shuffle", selected: false) {
                if standalone, let wallpaper = filtered.randomElement() { model.setWallpaper(wallpaper) }
                else { model.randomWallpaper() }
            }
        }.frame(height: 44).help(model.wallpaperArchiveStatus)
    }
    private var categoryBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 7) {
                ForEach(categories, id: \.self) { category in
                    WallpaperCategoryChip(model: model, name: category, preview: category == "All" ? model.wallpapers.first : model.wallpapers.first { $0.deletingLastPathComponent().lastPathComponent == category })
                }
            }.padding(.horizontal, 1)
        }.frame(height: 54)
    }
    private var homeView: some View {
        ZStack(alignment: .bottomLeading) {
            if !model.configuration.currentWallpaper.isEmpty { WallpaperHomeThumbnail(url: URL(fileURLWithPath: model.configuration.currentWallpaper)) }
            else { Color(hex: palette.surface) }
            LinearGradient(colors: [.clear, .black.opacity(0.78)], startPoint: .center, endPoint: .bottom)
            Text("\(model.wallpapers.count) wallpapers  •  \(model.configuration.favoriteWallpapers.count) favorites")
                .font(.caption.weight(.semibold)).foregroundStyle(.white.opacity(0.86)).padding(18)
        }.clipped().clipShape(RoundedRectangle(cornerRadius: 17, style: .continuous))
    }
    private var carouselView: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 6) { ForEach(Array(filtered.enumerated()), id: \.element) { index, url in WallpaperTile(model: model, url: url, selected: index == selectedIndex).frame(width: 286).id(index) } }.padding(.horizontal, 1)
            }.clipShape(RoundedRectangle(cornerRadius: 17)).onChange(of: model.wallpaperSelectionIndex) { _ in proxy.scrollTo(selectedIndex, anchor: .center) }
        }
    }
    private var gridView: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 190), spacing: 6)], spacing: 6) { ForEach(Array(filtered.enumerated()), id: \.element) { index, url in WallpaperTile(model: model, url: url, selected: index == selectedIndex).frame(height: 155).id(index) } }
        }.clipShape(RoundedRectangle(cornerRadius: 17))
    }
    private var emptyView: some View {
        VStack(spacing: 10) {
            Image(systemName: model.wallpaperViewMode == 2 ? "heart.slash" : "photo.on.rectangle.angled").font(.system(size: 38))
            Text(standalone || model.wallpaperViewMode == 2 ? "No favorite wallpapers" : "No wallpapers found").font(.headline)
            if standalone { Text("Favorite wallpapers from Ryft Settings to show them here.").font(.caption) }
            else { HStack { Button("Add wallpaper folder") { model.addWallpaperFolder() }; Button("Install GitHub collection") { model.installWallpaperArchive() }.disabled(model.installingWallpaperArchive) } }
            if !model.wallpaperArchiveStatus.isEmpty { Text(model.wallpaperArchiveStatus).font(.caption) }
        }
            .foregroundStyle(Color(hex: palette.muted)).frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    private var selectedIndex: Int { min(max(model.wallpaperSelectionIndex, 0), max(filtered.count - 1, 0)) }
    private func moveSelection(_ direction: MoveCommandDirection) {
        guard !filtered.isEmpty else { return }
        let step: Int
        switch direction { case .left: step = -1; case .right: step = 1; case .up: step = model.wallpaperGridMode ? -4 : -1; case .down: step = model.wallpaperGridMode ? 4 : 1; default: step = 0 }
        model.wallpaperSelectionIndex = min(max(selectedIndex + step, 0), filtered.count - 1)
    }
    private func applySelected() { if filtered.indices.contains(selectedIndex) { model.setWallpaper(filtered[selectedIndex]) } }
    private func toolbarButton(_ icon: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) { Image(systemName: icon).frame(width: 38, height: 38).background(selected ? Color(hex: palette.accent) : Color(hex: palette.surface)).foregroundStyle(selected ? Color(hex: palette.background) : Color(hex: palette.foreground)).clipShape(RoundedRectangle(cornerRadius: 12)) }.buttonStyle(SettingsHoverButtonStyle())
    }
}

private struct WallpaperHomeThumbnail: View {
    @StateObject private var thumbnail: WallpaperThumbnailLoader
    init(url: URL) { _thumbnail = StateObject(wrappedValue: WallpaperThumbnailLoader(url: url, size: CGSize(width: 1100, height: 640))) }
    var body: some View {
        Group {
            if let image = thumbnail.image { Image(nsImage: image).resizable().scaledToFill() }
            else { Color.clear }
        }
    }
}

private struct WallpaperCategoryChip: View {
    @ObservedObject var model: AppModel
    let name: String
    let preview: URL?
    @StateObject private var thumbnail: WallpaperThumbnailLoader
    init(model: AppModel, name: String, preview: URL?) {
        self.model = model; self.name = name; self.preview = preview
        _thumbnail = StateObject(wrappedValue: WallpaperThumbnailLoader(url: preview ?? URL(fileURLWithPath: "/dev/null"), size: CGSize(width: 150, height: 60)))
    }
    var body: some View {
        Button { model.wallpaperCategory = name; model.wallpaperSelectionIndex = 0 } label: {
            ZStack {
                if let image = thumbnail.image { Image(nsImage: image).resizable().scaledToFill().opacity(0.42) }
                Color(hex: model.configuration.bar.palette.surface).opacity(thumbnail.image == nil ? 1 : 0.42)
                Text(name).font(.caption.weight(.semibold)).lineLimit(1).padding(.horizontal, 12)
            }.frame(minWidth: 100, minHeight: 46).clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(model.wallpaperCategory == name ? Color(hex: model.configuration.bar.palette.accent) : .clear, lineWidth: 2))
        }.buttonStyle(SettingsHoverButtonStyle())
    }
}

private struct WallpaperTile: View {
    @ObservedObject var model: AppModel
    let url: URL
    let selected: Bool
    @StateObject private var thumbnail: WallpaperThumbnailLoader
    init(model: AppModel, url: URL, selected: Bool = false) { self.model = model; self.url = url; self.selected = selected; _thumbnail = StateObject(wrappedValue: WallpaperThumbnailLoader(url: url)) }
    var body: some View {
        ZStack(alignment: .topTrailing) {
            Button { model.setWallpaper(url) } label: {
                ZStack(alignment: .bottomLeading) {
                    if let image = thumbnail.image { Image(nsImage: image).resizable().scaledToFill() } else { Color(hex: model.configuration.bar.palette.surface); ProgressView() }
                }
            }.buttonStyle(SettingsHoverButtonStyle()).frame(maxWidth: .infinity, maxHeight: .infinity)
            Button { model.toggleFavorite(url) } label: { Image(systemName: model.isFavorite(url) ? "heart.fill" : "heart").foregroundStyle(.white).frame(width: 30, height: 30).background(.black.opacity(0.52)).clipShape(Circle()) }.buttonStyle(SettingsHoverButtonStyle()).padding(10)
        }.clipped().clipShape(RoundedRectangle(cornerRadius: 17, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 17).stroke(selected || model.configuration.currentWallpaper == url.path ? Color(hex: model.configuration.bar.palette.accent) : .clear, lineWidth: selected ? 4 : 3))
    }
}

struct GeneralSettingsView: View {
    @ObservedObject var model: AppModel
    @ObservedObject private var notifications: NotificationDaemon
    @ObservedObject private var permissions: RyftPermissionMonitor
    private var palette: ThemePalette { model.configuration.bar.palette }

    init(model: AppModel) {
        self.model = model
        notifications = model.notifications
        permissions = model.permissions
    }

    var body: some View {
        SettingsGroup("Permissions") {
            permissionRow(
                "Accessibility",
                detail: "Tiling, desktop switching, macOS controls, and reading explicitly selected text for Command+M.",
                symbol: "accessibility",
                granted: permissions.accessibilityGranted
            ) { WorkspaceController.requestAccessibility() }
            Divider()
            permissionRow(
                "Input Monitoring",
                detail: "Command+M and editable global shortcuts.",
                symbol: "keyboard",
                granted: permissions.inputMonitoringGranted
            ) { WorkspaceController.openPrivacyPane("Privacy_ListenEvent") }
            Divider()
            permissionRow(
                "Location for Wi-Fi",
                detail: "Nearby Wi-Fi names. Ryft never stores location data.",
                symbol: "location",
                granted: permissions.locationGranted
            ) {
                let status = CLLocationManager().authorizationStatus
                if status == .notDetermined { model.controls.requestWiFiAccessAndScan() }
                else { WorkspaceController.openPrivacyPane("Privacy_LocationServices") }
            }
            Divider()
            permissionRow(
                "Notifications",
                detail: "Ryft battery warnings.",
                symbol: "bell",
                granted: RyftPermissionStatus.notificationsGranted(status: notifications.authorizationStatus)
            ) {
                if notifications.authorizationStatus == "Not requested" { notifications.requestAuthorization() }
                else { WorkspaceController.openNotifications() }
            }
            Divider()
            permissionRow(
                "Screen Recording",
                detail: "Temporary in-memory frames for workspace slides and Command+M when no text is selected.",
                symbol: "rectangle.on.rectangle",
                granted: permissions.screenRecordingGranted
            ) {
                WorkspaceController.openPrivacyPane("Privacy_ScreenCapture")
            }
            Text("A red dot beside General remains visible while any permission needs attention. Select Review to open the matching macOS control.")
                .font(.caption).foregroundStyle(.secondary)
        }
        QuickStartSettingsView(model: model, embedded: true)
        SettingsGroup("Startup") {
            Toggle("Launch Ryft at login", isOn: Binding(get: { model.configuration.launchAtLogin }, set: { model.setLaunchAtLogin($0) }))
            Text("Login registration works after Ryft is installed as an application bundle.").font(.caption).foregroundStyle(.secondary)
        }
        SettingsGroup("Desktop experience") {
            Toggle("Use Hyprland cursor", isOn: $model.configuration.useHyprlandCursor)
            Text("Uses the source setup’s Bibata Modern Classic pointer across macOS. Turn it off at any time to restore the native cursor. This experimental overlay keeps one consistent arrow rather than replacing macOS text and resize cursors.").font(.caption).foregroundStyle(.secondary)
            Divider()
            Toggle("Ryft workspace slide", isOn: $model.configuration.experimentalWorkspaceTransitions)
            Text("Ryft-initiated desktop changes use a 220 ms Hyprland-style slide while the top bar stays fixed. Trackpad gestures retain Apple’s native animation, with the stationary Ryft bar layered above it. Screen Recording access is managed in Permissions above.").font(.caption).foregroundStyle(.secondary)
        }
        SettingsGroup("Profiles and saving") {
            HStack { Button("Save now") { model.save() }; Button("Import profile") { model.importProfile() }; Button("Export profile") { model.exportProfile() }; Spacer(); Button("Reset defaults", role: .destructive) { model.reset() } }
            Label("Every change is saved automatically", systemImage: "checkmark.circle.fill").foregroundStyle(Color(hex: model.configuration.bar.palette.success))
            Text("Saved to ~/Library/Application Support/Ryft/config.json. Profiles include the bar, widgets, blur, colors, shortcuts, favorites, tasks, and wallpaper sources.").font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
        }
        SettingsGroup("App identity and security") {
            LabeledContent("Local signing identity", value: "Termatica Release Signing")
            Text("Termatica signs local Ryft builds so macOS can retain Accessibility, Input Monitoring, Screen Recording, and Keychain trust across updates. It is never used to authenticate Gemini, request your Mac password, or access biometric data.").font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
        }
        SettingsGroup("Desktop integration") {
            LabeledContent("Bar engine", value: "Native AppKit + SwiftUI")
            LabeledContent("Default preset", value: "Classic")
            Text("The Classic preset maps the original Quickshell layout and palette to native macOS modules.").font(.caption).foregroundStyle(.secondary)
        }
        Divider().padding(.vertical, 4)
        Button(role: .destructive) { NSApp.terminate(nil) } label: { Label("Quit Ryft", systemImage: "power").frame(maxWidth: .infinity) }
            .buttonStyle(.bordered).controlSize(.large)
        EmptyView().onAppear { permissions.refresh(); notifications.refreshAuthorization() }
    }

    private func permissionRow(_ title: String, detail: String, symbol: String, granted: Bool, action: @escaping () -> Void) -> some View {
        HStack(spacing: 13) {
            Image(systemName: symbol).font(.system(size: 16, weight: .semibold)).foregroundStyle(Color(hex: palette.accent)).frame(width: 25)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).fontWeight(.semibold)
                Text(detail).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 16)
            Label(granted ? "Allowed" : "Needed", systemImage: granted ? "checkmark.circle.fill" : "circle.fill")
                .font(.caption.weight(.semibold))
                .foregroundStyle(granted ? Color(hex: palette.success) : Color.red)
            if !granted { Button("Review", action: action).buttonStyle(.bordered) }
        }
        .padding(.vertical, 3)
    }

}
