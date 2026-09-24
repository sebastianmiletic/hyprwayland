import AppKit
import CoreGraphics

enum TermaticaIntegrationService {
    static let bundleIdentifier = "com.termatica.Termatica"
    static let legacyLauncherBundleIdentifier = "com.termatica.DoubleCommandLauncher"

    static var applicationURL: URL? {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier)
            ?? (FileManager.default.fileExists(atPath: "/Applications/Termatica.app") ? URL(fileURLWithPath: "/Applications/Termatica.app") : nil)
    }

    static var isInstalled: Bool { applicationURL != nil }

    /// Ryft replaces the user's former standalone Command+Enter launcher when
    /// its built-in integration is enabled, avoiding two Carbon registrations.
    static func stopLegacyCommandLauncher() {
        // The previous helper was registered as a per-user launch job and may
        // immediately respawn after termination. Boot it out first, then end
        // any remaining process so Ryft can own Command+Enter without races.
        let launchctl = Process()
        launchctl.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        launchctl.arguments = ["bootout", "gui/\(getuid())/\(legacyLauncherBundleIdentifier)"]
        launchctl.standardOutput = FileHandle.nullDevice
        launchctl.standardError = FileHandle.nullDevice
        try? launchctl.run()
        launchctl.waitUntilExit()
        for application in NSRunningApplication.runningApplications(withBundleIdentifier: legacyLauncherBundleIdentifier) {
            _ = application.forceTerminate()
        }
    }

    static func openOrControl() {
        guard let appURL = applicationURL else { return }
        if let running = NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier).first {
            let command = hasVisibleWindowOnCurrentDesktop(pid: running.processIdentifier) ? "command-t" : "new-window"
            let cli = appURL.appendingPathComponent("Contents/MacOS/t")
            guard FileManager.default.isExecutableFile(atPath: cli.path) else {
                running.activate(options: [.activateAllWindows])
                return
            }
            let task = Process()
            task.executableURL = cli
            task.arguments = ["automation", command]
            task.terminationHandler = { task in
                DispatchQueue.main.async {
                    running.activate(options: task.terminationStatus == 0 ? [] : [.activateAllWindows])
                }
            }
            do { try task.run() }
            catch { running.activate(options: [.activateAllWindows]) }
            return
        }

        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.openApplication(at: appURL, configuration: configuration)
    }

    private static func hasVisibleWindowOnCurrentDesktop(pid: pid_t) -> Bool {
        guard let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[CFString: Any]] else { return false }
        return windows.contains { window in
            guard (window[kCGWindowOwnerPID] as? NSNumber)?.int32Value == pid,
                  (window[kCGWindowLayer] as? NSNumber)?.intValue == 0,
                  ((window[kCGWindowAlpha] as? NSNumber)?.doubleValue ?? 1) > 0,
                  let bounds = window[kCGWindowBounds] as? NSDictionary,
                  let frame = CGRect(dictionaryRepresentation: bounds) else { return false }
            return frame.width > 100 && frame.height > 100
        }
    }
}
