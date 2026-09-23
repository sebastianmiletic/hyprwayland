import AppKit
import Combine

/// Integrates Ryft with OmniWM's complete, notarized Hyprland-style Dwindle
/// engine instead of maintaining a second partial window manager. OmniWM stays
/// an independently signed application with its own permissions and GPL source.
final class OmniWMService: ObservableObject {
    @Published private(set) var installed = false
    @Published private(set) var running = false
    @Published private(set) var installing = false
    @Published private(set) var status = "Checking…"

    private let bundleID = "com.barut.OmniWM"
    private let releaseURL = URL(string: "https://github.com/OmniNull/OmniWM/releases/download/v0.7.1/OmniWM-v0.7.1.zip")!
    private var enabled = false
    private var timer: Timer?

    init() {
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in self?.refresh() }
    }

    deinit { timer?.invalidate() }

    var appURL: URL? {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Ryft/Engines/OmniWM.app")
        return [URL(fileURLWithPath: "/Applications/OmniWM.app"), FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications/OmniWM.app"), support]
            .first { FileManager.default.fileExists(atPath: $0.path) }
    }

    func setEnabled(_ value: Bool) {
        enabled = value
        if value { start() } else { stop() }
    }

    func refresh() {
        installed = appURL != nil
        running = !NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).isEmpty
        if installing { return }
        if !installed { status = "OmniWM is not installed" }
        else if running { status = enabled ? "Dwindle tiling is active" : "OmniWM is running independently" }
        else { status = enabled ? "Starting OmniWM…" : "Ready" }
    }

    func installAndEnable() {
        guard !installing else { return }
        installing = true; status = "Downloading OmniWM 0.7.1…"
        URLSession.shared.downloadTask(with: releaseURL) { [weak self] temporaryURL, _, error in
            guard let self else { return }
            guard let temporaryURL, error == nil else { DispatchQueue.main.async { self.installing = false; self.status = error?.localizedDescription ?? "Download failed" }; return }
            let fm = FileManager.default
            let staging = fm.temporaryDirectory.appendingPathComponent("Ryft-OmniWM-\(UUID().uuidString)", isDirectory: true)
            let support = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Ryft/Engines", isDirectory: true)
            do {
                try fm.createDirectory(at: staging, withIntermediateDirectories: true)
                try fm.createDirectory(at: support, withIntermediateDirectories: true)
                try Self.run("/usr/bin/ditto", ["-x", "-k", temporaryURL.path, staging.path])
                let source = staging.appendingPathComponent("OmniWM.app")
                guard Bundle(url: source)?.bundleIdentifier == self.bundleID else { throw InstallError.invalidBundle }
                try Self.run("/usr/bin/codesign", ["--verify", "--deep", "--strict", "-R", "=identifier \"com.barut.OmniWM\" and anchor apple generic and certificate leaf[subject.OU] = \"VF8LDJRGFM\"", source.path])
                let destination = support.appendingPathComponent("OmniWM.app")
                if fm.fileExists(atPath: destination.path) { try fm.removeItem(at: destination) }
                try fm.moveItem(at: source, to: destination)
                try? fm.removeItem(at: staging)
                DispatchQueue.main.async { self.installing = false; self.enabled = true; self.status = "OmniWM installed"; self.start() }
            } catch {
                try? fm.removeItem(at: staging)
                DispatchQueue.main.async { self.installing = false; self.status = "Install failed: \(error.localizedDescription)" }
            }
        }.resume()
    }

    func openOmniWM() {
        guard let appURL else { return }
        NSWorkspace.shared.openApplication(at: appURL, configuration: .init())
    }

    func openSource() {
        NSWorkspace.shared.open(URL(string: "https://github.com/OmniNull/OmniWM")!)
    }

    private func start() {
        guard let appURL else { status = "Install OmniWM to enable tiling"; return }
        NSWorkspace.shared.openApplication(at: appURL, configuration: .init()) { [weak self] _, error in
            DispatchQueue.main.async {
                if let error { self?.status = error.localizedDescription; return }
                self?.status = "Complete OmniWM’s permission setup if it appears"
                self?.configureDwindle(retries: 8)
            }
        }
    }

    private func stop() {
        NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).forEach { $0.terminate() }
        status = installed ? "Automatic tiling is off" : "OmniWM is not installed"
    }

    private func configureDwindle(retries: Int) {
        guard enabled else { return }
        let config = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".config/omniwm/settings.toml")
        guard var text = try? String(contentsOf: config, encoding: .utf8) else {
            if retries > 0 { DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in self?.configureDwindle(retries: retries - 1) } }
            return
        }
        text = replaceGeneralValue(in: text, key: "defaultLayoutType", value: "\"dwindle\"")
        text = replaceGeneralValue(in: text, key: "ipcEnabled", value: "true")
        text = replaceGeneralValue(in: text, key: "hotkeysEnabled", value: "false")
        do {
            try text.write(to: config, atomically: true, encoding: .utf8)
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in self?.setCurrentWorkspaceToDwindle(retries: retries) }
        } catch { status = "Could not configure OmniWM: \(error.localizedDescription)" }
    }

    private func replaceGeneralValue(in text: String, key: String, value: String) -> String {
        let pattern = "(?m)^\\s*\(NSRegularExpression.escapedPattern(for: key))\\s*=.*$"
        if let range = text.range(of: pattern, options: .regularExpression) { var copy = text; copy.replaceSubrange(range, with: "\(key) = \(value)"); return copy }
        guard let general = text.range(of: "[general]") else { return text }
        var copy = text; copy.insert(contentsOf: "\n\(key) = \(value)", at: general.upperBound); return copy
    }

    private func setCurrentWorkspaceToDwindle(retries: Int) {
        guard enabled, let appURL else { return }
        let cli = appURL.appendingPathComponent("Contents/MacOS/omniwmctl")
        do {
            try Self.run(cli.path, ["command", "set-workspace-layout", "dwindle"])
            status = "Dwindle tiling is active"
        } catch {
            if retries > 0 { DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in self?.setCurrentWorkspaceToDwindle(retries: retries - 1) } }
            else { status = "Finish OmniWM’s first-launch setup, then toggle tiling again" }
        }
    }

    private static func run(_ executable: String, _ arguments: [String]) throws {
        let process = Process(); process.executableURL = URL(fileURLWithPath: executable); process.arguments = arguments
        let pipe = Pipe(); process.standardError = pipe; process.standardOutput = pipe
        try process.run(); process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            let message = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? "Command failed"
            throw InstallError.command(message.trimmingCharacters(in: .whitespacesAndNewlines))
        }
    }

    private enum InstallError: LocalizedError {
        case invalidBundle, command(String)
        var errorDescription: String? { switch self { case .invalidBundle: "The downloaded application was not OmniWM"; case let .command(message): message.isEmpty ? "Verification failed" : message } }
    }
}
