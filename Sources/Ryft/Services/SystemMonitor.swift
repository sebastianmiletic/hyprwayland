import AppKit
import Combine
import CoreWLAN

struct AppResourceUsage: Identifiable {
    let id: pid_t
    let name: String
    let bundlePath: String
    let cpu: Double
    let memory: Double
    let memoryBytes: Int64
}

final class SystemMonitor: ObservableObject {
    @Published var activeApp = "Finder"
    @Published var wifi = "Wi-Fi"
    @Published var cpu = "--%"
    @Published var memory = "--%"
    @Published var uptime = "--"
    @Published var appUsage: [AppResourceUsage] = []

    private var timer: Timer?
    private var frontmostTimer: DispatchSourceTimer?
    private var workspaceObserver: NSObjectProtocol?
    private let iconCache = NSCache<NSString, NSImage>()

    init() {
        workspaceObserver = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] note in
            self?.setActiveApp((note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?.localizedName ?? "Desktop")
        }
        activeApp = NSWorkspace.shared.frontmostApplication?.localizedName ?? "Finder"
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in self?.refresh() }
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
    }

    private func refreshResourceUsage() {
        if let percent = physicalMemoryUsagePercent() { memory = "\(percent)%" }
        let apps = NSWorkspace.shared.runningApplications.filter { $0.activationPolicy == .regular && !$0.isTerminated }
        let appByPID = Dictionary(uniqueKeysWithValues: apps.map { ($0.processIdentifier, $0) })
        let physicalMemory = Double(ProcessInfo.processInfo.physicalMemory)
        run("ps", ["-axo", "pid=,ppid=,%cpu=,rss="]) { [weak self] text in
            struct ProcessUsage { let parent: pid_t; let cpu: Double; let rssKB: Int64 }
            var processes: [pid_t: ProcessUsage] = [:]
            for line in text.split(whereSeparator: \.isNewline) {
                let fields = line.split(whereSeparator: \.isWhitespace)
                guard fields.count >= 4, let pid = Int32(fields[0]), let parent = Int32(fields[1]), let cpu = Double(fields[2]), let rss = Int64(fields[3]) else { continue }
                processes[pid] = ProcessUsage(parent: parent, cpu: cpu, rssKB: rss)
            }
            var totals: [pid_t: (cpu: Double, rssKB: Int64)] = [:]
            for (pid, usage) in processes {
                var candidate = pid
                var visited = Set<pid_t>()
                while appByPID[candidate] == nil, let parent = processes[candidate]?.parent, parent > 0, !visited.contains(parent) {
                    visited.insert(candidate); candidate = parent
                }
                guard appByPID[candidate] != nil else { continue }
                totals[candidate, default: (0, 0)].cpu += usage.cpu
                totals[candidate, default: (0, 0)].rssKB += usage.rssKB
            }
            let totalCPU = processes.values.reduce(0) { $0 + $1.cpu }
            let normalizedCPU = min(100, totalCPU / Double(max(ProcessInfo.processInfo.activeProcessorCount, 1)))
            let result = apps.compactMap { app -> AppResourceUsage? in
                guard let usage = totals[app.processIdentifier] else { return nil }
                let bytes = usage.rssKB * 1024
                return AppResourceUsage(
                    id: app.processIdentifier,
                    name: app.localizedName ?? app.bundleIdentifier ?? "Application",
                    bundlePath: app.bundleURL?.path ?? "",
                    cpu: usage.cpu,
                    memory: physicalMemory > 0 ? Double(bytes) / physicalMemory * 100 : 0,
                    memoryBytes: bytes
                )
            }.sorted { ($0.cpu + $0.memory) > ($1.cpu + $1.memory) }
            self?.cpu = String(format: "%.0f%%", normalizedCPU)
            self?.appUsage = result
        }
    }

    private func physicalMemoryUsagePercent() -> Int? {
        var statistics = vm_statistics64_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &statistics) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }
        let usedPages = UInt64(statistics.active_count) + UInt64(statistics.inactive_count) + UInt64(statistics.wire_count) + UInt64(statistics.compressor_page_count)
        let usedBytes = Double(usedPages) * Double(vm_kernel_page_size)
        let total = Double(ProcessInfo.processInfo.physicalMemory)
        guard total > 0 else { return nil }
        return max(0, min(100, Int((usedBytes / total * 100).rounded())))
    }

    func icon(for app: AppResourceUsage) -> NSImage? {
        let key = (app.bundlePath.isEmpty ? "pid:\(app.id)" : app.bundlePath) as NSString
        if let icon = iconCache.object(forKey: key) { return icon }
        guard !app.bundlePath.isEmpty else { return NSRunningApplication(processIdentifier: app.id)?.icon }
        let icon = NSWorkspace.shared.icon(forFile: app.bundlePath)
        icon.size = NSSize(width: 32, height: 32)
        iconCache.setObject(icon, forKey: key)
        return icon
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
