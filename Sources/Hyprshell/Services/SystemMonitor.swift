import AppKit
import Combine
import CoreWLAN

struct AppResourceUsage: Identifiable {
    let id: pid_t
    let name: String
    let cpu: Double
    let memory: Double
}

final class SystemMonitor: ObservableObject {
    @Published var activeApp = "Finder"
    @Published var battery = "--"
    @Published var volume = "--"
    @Published var wifi = "Wi-Fi"
    @Published var cpu = "--%"
    @Published var memory = "--%"
    @Published var uptime = "--"
    @Published var appUsage: [AppResourceUsage] = []

    private var timer: Timer?
    private var frontmostTimer: DispatchSourceTimer?
    private var workspaceObserver: NSObjectProtocol?

    init() {
        workspaceObserver = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] note in
            self?.setActiveApp((note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?.localizedName ?? "Desktop")
        }
        activeApp = NSWorkspace.shared.frontmostApplication?.localizedName ?? "Finder"
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in self?.refresh() }
        let frontmost = DispatchSource.makeTimerSource(queue: .main)
        frontmost.schedule(deadline: .now(), repeating: .milliseconds(80), leeway: .milliseconds(8))
        frontmost.setEventHandler { [weak self] in self?.setActiveApp(NSWorkspace.shared.frontmostApplication?.localizedName ?? "Desktop") }
        frontmost.resume(); frontmostTimer = frontmost
    }

    deinit {
        if let workspaceObserver { NSWorkspace.shared.notificationCenter.removeObserver(workspaceObserver) }
        timer?.invalidate()
        frontmostTimer?.cancel()
    }

    private func setActiveApp(_ name: String) { if activeApp != name { activeApp = name } }

    func refresh() {
        wifi = CWWiFiClient.shared().interface()?.ssid() ?? "Wi-Fi"
        refreshResourceUsage()
        let hours = Int(ProcessInfo.processInfo.systemUptime / 3600)
        uptime = hours < 24 ? "\(hours)h" : "\(hours / 24)d"
        run("pmset", ["-g", "batt"]) { [weak self] text in
            if let percent = text.range(of: #"\d+%"#, options: .regularExpression).map({ String(text[$0]) }) { self?.battery = percent }
        }
        run("osascript", ["-e", "output volume of (get volume settings)"]) { [weak self] text in self?.volume = text.trimmingCharacters(in: .whitespacesAndNewlines) + "%" }
    }

    private func refreshResourceUsage() {
        run("ps", ["-A", "-o", "%cpu="]) { [weak self] text in
            let total = text.split(whereSeparator: \.isNewline).compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }.reduce(0, +)
            let normalized = min(100, total / Double(max(ProcessInfo.processInfo.activeProcessorCount, 1)))
            self?.cpu = String(format: "%.0f%%", normalized)
        }
        run("memory_pressure", ["-Q"]) { [weak self] text in
            guard let range = text.range(of: #"free percentage:\s*(\d+)%"#, options: [.regularExpression, .caseInsensitive]) else { return }
            let match = String(text[range]); let free = Int(match.filter(\.isNumber)) ?? 0
            self?.memory = "\(max(0, min(100, 100 - free)))%"
        }
        let apps = NSWorkspace.shared.runningApplications.filter { $0.activationPolicy == .regular && !$0.isTerminated }
        run("ps", ["-axo", "pid=,%cpu=,%mem="]) { [weak self] text in
            var values: [pid_t: (Double, Double)] = [:]
            for line in text.split(whereSeparator: \.isNewline) {
                let fields = line.split(whereSeparator: \.isWhitespace)
                guard fields.count >= 3, let pid = Int32(fields[0]), let cpu = Double(fields[1]), let memory = Double(fields[2]) else { continue }
                values[pid] = (cpu, memory)
            }
            self?.appUsage = apps.compactMap { app in
                guard let usage = values[app.processIdentifier] else { return nil }
                return AppResourceUsage(id: app.processIdentifier, name: app.localizedName ?? app.bundleIdentifier ?? "Application", cpu: usage.0, memory: usage.1)
            }.sorted { ($0.cpu + $0.memory) > ($1.cpu + $1.memory) }
        }
    }

    private func run(_ executable: String, _ arguments: [String], completion: @escaping (String) -> Void) {
        DispatchQueue.global(qos: .utility).async {
            let process = Process(); let pipe = Pipe()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            process.arguments = [executable] + arguments; process.standardOutput = pipe; process.standardError = Pipe()
            do {
                try process.run(); process.waitUntilExit()
                let value = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                DispatchQueue.main.async { completion(value) }
            } catch {}
        }
    }
}
