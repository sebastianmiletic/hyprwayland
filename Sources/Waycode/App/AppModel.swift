import AppKit
import Combine
import ServiceManagement
import UniformTypeIdentifiers
import CoreWLAN

final class AppModel: ObservableObject {
    static let shared = AppModel()

    @Published var configuration: WaycodeConfiguration
    @Published var wallpapers: [URL] = []
    @Published var selectedSection: AppSection = .bar
    @Published var barProfileName = "My bar"
    @Published var selectedWorkspace = 1
    @Published var selectedEditorWidget: UUID?
    @Published var wallpaperSearch = ""
    @Published var wallpaperViewMode = 1
    @Published var wallpaperGridMode = false
    @Published var wallpaperCategory = "All"
    @Published var wallpaperSelectionIndex = 0
    @Published var sidebarTab = 0
    @Published var sidebarVolume: Double = 50
    @Published var todoDraft = ""
    @Published var toolQuery = ""
    @Published var rightSidebarDetail = ""
    @Published var selectedWiFiID = ""
    @Published var wifiPassword = ""
    @Published var statusPopoverWidgetID: UUID? = nil
    @Published var statusPopoverInteractionID: UUID? = nil
    @Published var statusPopoverDetail = ""
    @Published var statusMessage = "Ready"
    @Published var wallpaperArchiveStatus = ""
    @Published var installingWallpaperArchive = false
    let system = SystemMonitor()
    let controls = SystemControlService()
    lazy var notifications = NotificationDaemon(controls: controls)
    let workspaces = WorkspaceService()
    let tiling = TilingService()
    let gemini = GeminiService()

    private var cancellables = Set<AnyCancellable>()
    private var wallpaperScanToken = UUID()
    private let configURL: URL

    private init() {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Waycode", isDirectory: true)
        try? FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
        configURL = support.appendingPathComponent("config.json")
        if let data = try? Data(contentsOf: configURL), let decoded = try? JSONDecoder().decode(WaycodeConfiguration.self, from: data) {
            configuration = decoded
        } else {
            configuration = WaycodeConfiguration()
        }
        if configuration.currentWallpaper.isEmpty, let screen = NSScreen.main, let current = NSWorkspace.shared.desktopImageURL(for: screen) { configuration.currentWallpaper = current.path }
        if configuration.sourcePresetVersion < 2 {
            configuration.bar.palette = .sebastian
            configuration.bar.widgets = WidgetConfiguration.defaults
            configuration.bar.height = 38
            configuration.bar.cornerRadius = 17
            configuration.bar.itemSpacing = 4
            configuration.bar.reserveNotchSpace = true
            configuration.bar.splitAroundNotch = true
            configuration.sourcePresetVersion = 2
        }
        if configuration.sourcePresetVersion < 3 {
            configuration.bar.height = 42
            configuration.bar.outerInset = 5
            configuration.bar.horizontalInset = 5
            configuration.bar.cornerRadius = 18
            configuration.bar.itemSpacing = 4
            configuration.bar.widgets = WidgetConfiguration.defaults
            configuration.sourcePresetVersion = 3
        }
        if configuration.sourcePresetVersion < 4 {
            configuration.bar.horizontalInset = 12
            if !configuration.shortcuts.contains(where: { $0.action == .tileWindows }) {
                configuration.shortcuts.append(ShortcutConfiguration(action: .tileWindows, key: "t", option: true, command: false, control: true))
            }
            configuration.sourcePresetVersion = 4
        }
        if configuration.sourcePresetVersion < 5 {
            // Fixed alpha is the default because NSVisualEffectView can alter
            // material emphasis during a Space transition. Blur remains optional.
            configuration.bar.blurEnabled = false
            configuration.sourcePresetVersion = 5
        }
        if configuration.sourcePresetVersion < 6 {
            if !configuration.shortcuts.contains(where: { $0.action == .openFinder }) {
                configuration.shortcuts.append(ShortcutConfiguration(action: .openFinder, key: "e", option: false, command: true))
            }
            configuration.sourcePresetVersion = 6
        }
        if configuration.sourcePresetVersion < 7 {
            // Repair actions from older profiles where status widgets decoded as inert.
            for index in configuration.bar.widgets.indices {
                switch configuration.bar.widgets[index].kind {
                case .leftSidebar: configuration.bar.widgets[index].clickAction = .leftSidebar
                case .wifi, .volume, .battery, .rightSidebar, .clock: configuration.bar.widgets[index].clickAction = .rightSidebar
                case .settings: configuration.bar.widgets[index].clickAction = .settings
                default: break
                }
            }
            configuration.bar.blurEnabled = false
            configuration.bar.notchShelfCornerRadius = 0
            configuration.sourcePresetVersion = 7
        }
        if configuration.sourcePresetVersion < 8 {
            configuration.tiling.layout = .dwindle
            configuration.sourcePresetVersion = 8
        }
        if configuration.sourcePresetVersion < 9 {
            configuration.tiling.autoTile = configuration.tiling.enabled
            configuration.sourcePresetVersion = 9
        }
        if configuration.sourcePresetVersion < 10 {
            for shortcut in [
                ShortcutConfiguration(action: .leftSidebar, key: "a"),
                ShortcutConfiguration(action: .rightSidebar, key: "n"),
                ShortcutConfiguration(action: .quitFrontmost, key: "q", option: false, command: true)
            ] where !configuration.shortcuts.contains(where: { $0.action == shortcut.action }) { configuration.shortcuts.append(shortcut) }
            if !configuration.bar.showBackground, configuration.bar.widgets.first(where: { $0.kind == .rightSidebar })?.style == .pill {
                for index in configuration.bar.widgets.indices {
                    if [.wifi, .volume, .battery].contains(configuration.bar.widgets[index].kind) { configuration.bar.widgets[index].enabled = false }
                    if configuration.bar.widgets[index].kind == .settings { configuration.bar.widgets[index].style = .plain }
                    if configuration.bar.widgets[index].kind == .rightSidebar { configuration.bar.widgets[index].icon = "slider.horizontal.3"; configuration.bar.widgets[index].showLabel = false }
                }
            }
            configuration.sourcePresetVersion = 10
        }
        if !configuration.bar.widgets.contains(where: { $0.kind == .settings || $0.clickAction == .settings }) {
            configuration.bar.widgets.append(WidgetConfiguration(kind: .settings, name: "Waycode settings", placement: .trailing, icon: "gearshape.fill", showLabel: false, clickAction: .settings))
        }
        $configuration.dropFirst().debounce(for: .milliseconds(180), scheduler: RunLoop.main).sink { [weak self] value in
            self?.save(value)
        }.store(in: &cancellables)
        $configuration.map(\.tiling).removeDuplicates().sink { [weak self] in self?.tiling.update($0) }.store(in: &cancellables)
        $configuration.map { ($0.wallpaperFolders + ["|"] + $0.wallpaperFiles).joined(separator: "\u{0}") }
            .removeDuplicates().dropFirst().debounce(for: .milliseconds(250), scheduler: RunLoop.main)
            .sink { [weak self] _ in self?.refreshWallpapers() }.store(in: &cancellables)
        tiling.update(configuration.tiling)
        refreshWallpapers()
        save()
    }

    func save(_ value: WaycodeConfiguration? = nil) {
        do {
            let data = try JSONEncoder.pretty.encode(value ?? configuration)
            try data.write(to: configURL, options: .atomic)
            statusMessage = "Saved"
        } catch { statusMessage = "Could not save: \(error.localizedDescription)" }
    }

    func reset() { configuration = WaycodeConfiguration() }

    func barConfiguration(for style: BuiltInBarStyle) -> BarConfiguration {
        var bar = configuration.bar
        bar.apply(style)
        return bar
    }
    func applyBarStyle(_ style: BuiltInBarStyle) {
        configuration.bar = barConfiguration(for: style)
        statusMessage = "Applied \(style.rawValue)"
    }

    func saveBarProfile() {
        let name = barProfileName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        configuration.savedBars.append(NamedBarProfile(name: name, bar: configuration.bar)); statusMessage = "Saved bar profile"
    }
    func applyBarProfile(_ profile: NamedBarProfile) { configuration.bar = profile.bar; statusMessage = "Loaded \(profile.name)" }

    func exportProfile() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "Waycode-profile.json"
        panel.allowedContentTypes = [.json]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try JSONEncoder.pretty.encode(configuration).write(to: url, options: .atomic)
            statusMessage = "Profile exported"
        } catch { statusMessage = error.localizedDescription }
    }

    func importProfile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            configuration = try JSONDecoder().decode(WaycodeConfiguration.self, from: Data(contentsOf: url))
            statusMessage = "Profile imported"
        } catch { statusMessage = "Invalid profile: \(error.localizedDescription)" }
    }

    func addWallpaperFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let path = panel.url?.path else { return }
        if !configuration.wallpaperFolders.contains(path) { configuration.wallpaperFolders.append(path) }
    }

    func addWallpaperFiles() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = true
        panel.allowedContentTypes = [.image]
        guard panel.runModal() == .OK else { return }
        let additions = panel.urls.map(\.path).filter { !configuration.wallpaperFiles.contains($0) }
        configuration.wallpaperFiles.append(contentsOf: additions)
    }

    func refreshWallpapers() {
        let folders = configuration.wallpaperFolders
        let files = configuration.wallpaperFiles
        let token = UUID(); wallpaperScanToken = token
        DispatchQueue.global(qos: .utility).async {
            let keys: Set<URLResourceKey> = [.isRegularFileKey]
            var found: [URL] = []
            let allowed = Set(["jpg", "jpeg", "png", "heic", "webp", "tiff", "avif", "bmp"])
            scan: for folder in folders {
                guard let enumerator = FileManager.default.enumerator(at: URL(fileURLWithPath: folder), includingPropertiesForKeys: Array(keys), options: [.skipsHiddenFiles, .skipsPackageDescendants]) else { continue }
                for case let url as URL in enumerator where allowed.contains(url.pathExtension.lowercased()) {
                    found.append(url)
                    if found.count >= 5000 { break scan }
                }
            }
            found.append(contentsOf: files.map { URL(fileURLWithPath: $0) }.filter { FileManager.default.fileExists(atPath: $0.path) })
            let result = Array(Set(found).sorted { $0.path.localizedStandardCompare($1.path) == .orderedAscending }.prefix(5000))
            DispatchQueue.main.async { if self.wallpaperScanToken == token { self.wallpapers = result } }
        }
    }

    func isFavorite(_ url: URL) -> Bool { configuration.favoriteWallpapers.contains(url.path) }
    func toggleFavorite(_ url: URL) {
        if let index = configuration.favoriteWallpapers.firstIndex(of: url.path) { configuration.favoriteWallpapers.remove(at: index) }
        else { configuration.favoriteWallpapers.append(url.path) }
    }

    func setWallpaper(_ url: URL) {
        var failures = 0
        let options: [NSWorkspace.DesktopImageOptionKey: Any] = [.imageScaling: NSImageScaling.scaleProportionallyUpOrDown.rawValue, .allowClipping: true]
        for screen in NSScreen.screens {
            do { try NSWorkspace.shared.setDesktopImageURL(url, for: screen, options: options) }
            catch { failures += 1 }
        }
        // Also asks Finder/System Events to update every Mission Control desktop.
        // NSWorkspace covers current desktops; this fills the all-Spaces gap.
        let escaped = url.path.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        let script = "tell application \"System Events\" to tell every desktop to set picture to \"\(escaped)\""
        var scriptError: NSDictionary?; NSAppleScript(source: script)?.executeAndReturnError(&scriptError)
        if failures == 0 {
            configuration.currentWallpaper = url.path
            statusMessage = "Wallpaper changed"
            if configuration.adaptColorsToWallpaper {
                let base = configuration.bar.palette
                DispatchQueue.global(qos: .userInitiated).async {
                    guard let palette = WallpaperColorExtractor.palette(from: url, basedOn: base) else { return }
                    DispatchQueue.main.async { self.configuration.bar.palette = palette }
                }
            }
            NotificationCenter.default.post(name: .waycodeWallpaperChanged, object: url)
        } else { statusMessage = "Wallpaper failed on \(failures) display(s)" }
    }

    func installWallpaperArchive() {
        guard !installingWallpaperArchive else { return }
        installingWallpaperArchive = true; wallpaperArchiveStatus = "Downloading ItsTerm1n4l wallpaper archive…"
        let destination = configURL.deletingLastPathComponent().appendingPathComponent("Wallpapers/TerminalArchive", isDirectory: true)
        guard let remote = URL(string: "https://codeload.github.com/ItsTerm1n4l/Wallpapers-old-archive/zip/refs/heads/main") else { return }
        URLSession.shared.downloadTask(with: remote) { temporary, _, error in
            guard let temporary, error == nil else {
                DispatchQueue.main.async { self.installingWallpaperArchive = false; self.wallpaperArchiveStatus = "Archive download failed. Check your connection." }; return
            }
            let staging = FileManager.default.temporaryDirectory.appendingPathComponent("WaycodeWallpapers-\(UUID().uuidString)", isDirectory: true)
            do {
                try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
                let process = Process(); process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto"); process.arguments = ["-x", "-k", temporary.path, staging.path]
                try process.run(); process.waitUntilExit()
                guard process.terminationStatus == 0,
                      let extracted = try FileManager.default.contentsOfDirectory(at: staging, includingPropertiesForKeys: nil).first(where: { $0.hasDirectoryPath }) else { throw CocoaError(.fileReadCorruptFile) }
                try? FileManager.default.removeItem(at: destination)
                try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
                try FileManager.default.moveItem(at: extracted, to: destination)
                try? FileManager.default.removeItem(at: staging)
                DispatchQueue.main.async {
                    if !self.configuration.wallpaperFolders.contains(destination.path) { self.configuration.wallpaperFolders.append(destination.path) }
                    self.installingWallpaperArchive = false; self.wallpaperArchiveStatus = "Archive installed with its original categories."
                    self.wallpaperCategory = "All"; self.refreshWallpapers()
                }
            } catch {
                try? FileManager.default.removeItem(at: staging)
                DispatchQueue.main.async { self.installingWallpaperArchive = false; self.wallpaperArchiveStatus = "Could not unpack archive: \(error.localizedDescription)" }
            }
        }.resume()
    }

    func randomWallpaper() {
        if let url = wallpapers.randomElement() { setWallpaper(url) }
        else { statusMessage = "Add a folder containing images first" }
    }

    func setVolume(_ value: Double) {
        sidebarVolume = value
        controls.setOutputVolume(value)
    }
    func toggleMute() { runUtility("osascript", ["-e", "set volume output muted not (output muted of (get volume settings))"]) }
    func toggleWiFi() {
        guard let interface = CWWiFiClient.shared().interface() else { return }
        try? interface.setPower(!interface.powerOn())
        system.refresh()
    }
    func toggleAppearance() { runUtility("osascript", ["-e", "tell application \"System Events\" to tell appearance preferences to set dark mode to not dark mode"]) }
    func openNotificationCenter() {
        guard let source = CGEventSource(stateID: .hidSystemState),
              let down = CGEvent(keyboardEventSource: source, virtualKey: 45, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: 45, keyDown: false) else { return }
        down.flags = .maskSecondaryFn; up.flags = .maskSecondaryFn
        down.post(tap: .cghidEventTap); up.post(tap: .cghidEventTap)
    }
    func openSystemSettings(_ pane: String = "") {
        let target = pane.isEmpty ? "x-apple.systempreferences:" : "x-apple.systempreferences:com.apple.\(pane)"
        if let url = URL(string: target) { NSWorkspace.shared.open(url) }
    }
    func addTodo() {
        let value = todoDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return }; configuration.todos.append(value); todoDraft = ""
    }
    func runTool(mode: Int) {
        let query = toolQuery.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        let target = mode == 1 ? "https://translate.google.com/?sl=auto&tl=en&text=\(query)&op=translate" : "https://www.google.com/search?q=\(query)"
        if let url = URL(string: target) { NSWorkspace.shared.open(url) }
    }
    private func runUtility(_ executable: String, _ arguments: [String]) {
        let process = Process(); process.executableURL = URL(fileURLWithPath: "/usr/bin/env"); process.arguments = [executable] + arguments; try? process.run()
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        if #available(macOS 13.0, *) {
            do {
                if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
                configuration.launchAtLogin = enabled
            } catch { statusMessage = "Login item unavailable in development builds" }
        }
    }
}

enum AppSection: String, CaseIterable, Identifiable {
    case bar = "Bar", themes = "Themes", modules = "Widgets", tiling = "Tiling", shortcuts = "Keybinds", wallpapers = "Wallpapers", general = "General"
    var id: String { rawValue }
    var symbol: String {
        switch self {
        case .bar: "menubar.rectangle"; case .themes: "paintpalette"; case .modules: "square.grid.2x2"
        case .tiling: "rectangle.split.2x1"; case .shortcuts: "command"; case .wallpapers: "photo.on.rectangle.angled"; case .general: "gearshape"
        }
    }
}

extension JSONEncoder {
    static var pretty: JSONEncoder { let e = JSONEncoder(); e.outputFormatting = [.prettyPrinted, .sortedKeys]; return e }
}
