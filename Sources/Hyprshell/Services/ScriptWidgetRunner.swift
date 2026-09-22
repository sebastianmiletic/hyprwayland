import Foundation
import Combine

final class ScriptWidgetRunner: ObservableObject {
    @Published var output = "…"
    private var timer: Timer?
    private let command: String

    init(command: String, interval: Double) {
        self.command = command
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: max(interval, 2), repeats: true) { [weak self] _ in self?.refresh() }
    }
    deinit { timer?.invalidate() }

    func refresh() {
        guard !command.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { output = "Script"; return }
        DispatchQueue.global(qos: .utility).async {
            let process = Process(); let pipe = Pipe()
            process.executableURL = URL(fileURLWithPath: "/bin/zsh")
            process.arguments = ["-lc", self.command]
            process.standardOutput = pipe; process.standardError = Pipe()
            do {
                try process.run(); process.waitUntilExit()
                let text = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                DispatchQueue.main.async { self.output = text.components(separatedBy: .newlines).first ?? "" }
            } catch { DispatchQueue.main.async { self.output = "Error" } }
        }
    }

    static func runAction(_ command: String) {
        guard !command.isEmpty else { return }
        let process = Process(); process.executableURL = URL(fileURLWithPath: "/bin/zsh"); process.arguments = ["-lc", command]
        try? process.run()
    }
}

extension Notification.Name {
    static let hyprshellShowWallpapers = Notification.Name("Hyprshell.showWallpapers")
    static let hyprshellShowSettings = Notification.Name("Hyprshell.showSettings")
    static let hyprshellToggleLeftSidebar = Notification.Name("Hyprshell.toggleLeftSidebar")
    static let hyprshellToggleRightSidebar = Notification.Name("Hyprshell.toggleRightSidebar")
    static let hyprshellWallpaperChanged = Notification.Name("Hyprshell.wallpaperChanged")
}
