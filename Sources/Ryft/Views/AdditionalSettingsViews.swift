import SwiftUI
import AppKit
import UniformTypeIdentifiers
import ApplicationServices
import CoreLocation

struct ShortcutSettingsView: View {
    @ObservedObject var model: AppModel
    private let keys = GlobalHotkeyManager.keyCodes.keys.sorted()
    var body: some View {
        SettingsGroup("Global shortcuts") {
            ForEach(Array(model.configuration.shortcuts.indices), id: \.self) { index in
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 10) {
                        Picker("Action", selection: $model.configuration.shortcuts[index].action) { ForEach(ShortcutAction.allCases.filter { $0 != .wallpaper && $0 != .randomWallpaper && $0 != .screenAnswer }) { Text($0.rawValue).tag($0) } }.labelsHidden().frame(width: 170)
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
        case .quitFrontmost: _ = NSWorkspace.shared.frontmostApplication?.terminate()
        }
    }
}

struct WallpaperGalleryView: View {
    @ObservedObject var model: AppModel
    let standalone: Bool
    private var palette: ThemePalette { model.configuration.bar.palette }
    private var categories: [String] { ["All"] + Array(Set(model.wallpapers.map { $0.deletingLastPathComponent().lastPathComponent }).subtracting(["All", "assets"])).sorted() }
    private var filtered: [URL] {
        let categorized = model.wallpaperCategory == "All" ? model.wallpapers : model.wallpapers.filter { $0.deletingLastPathComponent().lastPathComponent == model.wallpaperCategory }
        let searched = model.wallpaperSearch.isEmpty ? categorized : categorized.filter { $0.lastPathComponent.localizedCaseInsensitiveContains(model.wallpaperSearch) }
        return model.wallpaperViewMode == 2 ? searched.filter(model.isFavorite) : searched
    }

    var body: some View {
        VStack(spacing: 12) {
            toolbar
            if model.wallpaperViewMode != 0 { categoryBar }
            Group {
                if model.wallpaperViewMode == 0 { homeView }
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
    }

    private var toolbar: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 1) {
                Text("RYFT").font(.caption2.weight(.bold)).tracking(2).foregroundStyle(Color(hex: palette.accent))
                Text("Wallpaper library").font(.title3.weight(.semibold))
            }.frame(width: 170, alignment: .leading)
            toolbarButton("house.fill", selected: model.wallpaperViewMode == 0) { model.wallpaperViewMode = 0 }
            HStack(spacing: 8) { Image(systemName: "magnifyingglass").foregroundStyle(Color(hex: palette.muted)); TextField("Search the library", text: $model.wallpaperSearch).textFieldStyle(.plain); if !model.wallpaperSearch.isEmpty { Button { model.wallpaperSearch = "" } label: { Image(systemName: "xmark.circle.fill") }.buttonStyle(SettingsHoverButtonStyle()).foregroundStyle(Color(hex: palette.muted)) } }
                .padding(.horizontal, 12).frame(maxWidth: .infinity).frame(height: 40).background(Color(hex: palette.surface)).clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
            toolbarButton(model.wallpaperGridMode ? "rectangle.split.3x3" : "rectangle.split.3x1", selected: model.wallpaperGridMode) { model.wallpaperGridMode.toggle(); model.wallpaperViewMode = 1 }
            toolbarButton(model.wallpaperViewMode == 2 ? "heart.fill" : "heart", selected: model.wallpaperViewMode == 2) { model.wallpaperViewMode = model.wallpaperViewMode == 2 ? 1 : 2 }
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
            toolbarButton("shuffle", selected: false) { model.randomWallpaper() }
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
            Text(model.wallpaperViewMode == 2 ? "No favorite wallpapers" : "No wallpapers found").font(.headline)
            if standalone { Text("Add wallpaper folders in Ryft Settings.").font(.caption) }
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
                detail: "Desktop switching and macOS control actions.",
                symbol: "accessibility",
                granted: permissions.accessibilityGranted
            ) { WorkspaceController.requestAccessibility() }
            Divider()
            permissionRow(
                "Input Monitoring",
                detail: "Global Option+A, Option+N, Command+M, and desktop shortcuts.",
                symbol: "keyboard",
                granted: permissions.inputMonitoringGranted
            ) { openPrivacyPane("Privacy_ListenEvent") }
            Divider()
            permissionRow(
                "Location for Wi-Fi",
                detail: "Nearby Wi-Fi names. Ryft never stores location data.",
                symbol: "location",
                granted: permissions.locationGranted
            ) {
                let status = CLLocationManager().authorizationStatus
                if status == .notDetermined { model.controls.requestWiFiAccessAndScan() }
                else { openPrivacyPane("Privacy_LocationServices") }
            }
            Divider()
            permissionRow(
                "Notifications",
                detail: "Ryft battery warnings.",
                symbol: "bell",
                granted: RyftPermissionStatus.notificationsGranted(status: notifications.authorizationStatus)
            ) {
                if notifications.authorizationStatus == "Not requested" { notifications.requestAuthorization() }
                else if let url = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension") { NSWorkspace.shared.open(url) }
            }
            Divider()
            permissionRow(
                "Screen Recording",
                detail: "Temporary in-memory frames for workspace slides and Command+M visual answers.",
                symbol: "rectangle.on.rectangle",
                granted: permissions.screenRecordingGranted
            ) {
                openPrivacyPane("Privacy_ScreenCapture")
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
        SettingsGroup("Desktop integration") {
            LabeledContent("Bar engine", value: "Native AppKit + SwiftUI")
            LabeledContent("Imported preset", value: "Sebastian II")
            Text("Sebastian II is ported from github.com/sebastianmiletic/hyprland-dotfiles at commit bb7de91. The upstream desktop uses Quickshell, not Waybar, so Ryft maps its layout and palette to native macOS modules.").font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
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

    private func openPrivacyPane(_ pane: String) {
        NSApp.keyWindow?.orderOut(nil)
        let legacy = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)")
        let modern = URL(string: "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?\(pane)")
        let target = ProcessInfo.processInfo.operatingSystemVersion.majorVersion >= 13 ? (modern ?? legacy) : legacy
        guard let target else { return }
        NSWorkspace.shared.open(target, configuration: NSWorkspace.OpenConfiguration()) { _, error in
            guard error != nil, let legacy, legacy != target else { return }
            NSWorkspace.shared.open(legacy)
        }
    }
}
