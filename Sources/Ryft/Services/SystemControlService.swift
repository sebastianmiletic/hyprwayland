import AppKit
import Combine
import CoreAudio
import CoreLocation
import CoreWLAN

struct WiFiNetworkInfo: Identifiable, Hashable {
    let id: String
    let ssid: String
    let signal: Int
    let secure: Bool
    let network: CWNetwork
}

struct AudioDeviceInfo: Identifiable, Hashable {
    let id: AudioDeviceID
    let name: String
}

final class SystemControlService: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published var wifiEnabled = false
    @Published var connectedSSID = "Not connected"
    @Published var wifiNetworks: [WiFiNetworkInfo] = []
    @Published var scanningWiFi = false
    @Published var audioDevices: [AudioDeviceInfo] = []
    @Published var defaultAudioDevice: AudioDeviceID = 0
    @Published var outputVolume: Double = 50
    @Published var lowPowerMode = false
    @Published var batteryPercent = "--"
    @Published var batteryLevel = -1
    @Published var batteryCharging = false
    @Published var operationMessage = ""

    // Core Location must be created after NSApplication has finished launching.
    // Constructing it during SwiftUI's early model initialization gives
    // locationd an empty bundle identity, so macOS cannot persist its decision.
    private lazy var locationManager: CLLocationManager = {
        let manager = CLLocationManager(); manager.delegate = self; return manager
    }()
    private var levelTimer: Timer?
    private var powerTimer: Timer?

    override init() {
        super.init()
        refreshAll()
        levelTimer = Timer.scheduledTimer(withTimeInterval: 0.35, repeats: true) { [weak self] _ in self?.refreshOutputLevel() }
        powerTimer = Timer.scheduledTimer(withTimeInterval: 15, repeats: true) { [weak self] _ in self?.refreshPowerState() }
    }
    deinit { levelTimer?.invalidate(); powerTimer?.invalidate() }

    func refreshAll() {
        refreshWiFiState(); refreshAudioDevices(); refreshPowerState()
    }

    func requestWiFiAccessAndScan() {
        switch locationManager.authorizationStatus {
        case .authorized, .authorizedAlways: scanWiFi()
        case .notDetermined:
            let key = "RyftRequestedWiFiLocation"
            if !UserDefaults.standard.bool(forKey: key) { UserDefaults.standard.set(true, forKey: key); locationManager.requestAlwaysAuthorization() }
            else { operationMessage = "Allow Location once to list nearby Wi-Fi networks." }
        case .denied, .restricted: operationMessage = "Allow Location in Privacy & Security to list nearby Wi-Fi networks."
        @unknown default: operationMessage = "Nearby Wi-Fi networks are unavailable."
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        if manager.authorizationStatus == .authorized { scanWiFi() }
    }

    func refreshWiFiState() {
        guard let interface = CWWiFiClient.shared().interface() else { return }
        wifiEnabled = interface.powerOn()
        connectedSSID = interface.ssid() ?? "Not connected"
    }

    func setWiFiEnabled(_ enabled: Bool) {
        guard let interface = CWWiFiClient.shared().interface() else { return }
        do { try interface.setPower(enabled); refreshWiFiState(); if enabled { scanWiFi() } }
        catch { operationMessage = "Wi-Fi: \(error.localizedDescription)" }
    }

    func scanWiFi() {
        guard let interface = CWWiFiClient.shared().interface(), interface.powerOn() else { wifiNetworks = []; return }
        scanningWiFi = true
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let results = try interface.scanForNetworks(withSSID: nil)
                let mapped = results.compactMap { network -> WiFiNetworkInfo? in
                    guard let ssid = network.ssid, !ssid.isEmpty else { return nil }
                    return WiFiNetworkInfo(id: "\(ssid)-\(network.bssid ?? "")", ssid: ssid, signal: network.rssiValue, secure: !network.supportsSecurity(.none), network: network)
                }.sorted { $0.signal > $1.signal }
                var seen = Set<String>()
                let unique = mapped.filter { seen.insert($0.ssid).inserted }
                DispatchQueue.main.async { self.wifiNetworks = unique; self.scanningWiFi = false; self.refreshWiFiState() }
            } catch { DispatchQueue.main.async { self.operationMessage = "Wi-Fi scan: \(error.localizedDescription)"; self.scanningWiFi = false } }
        }
    }

    func connect(to info: WiFiNetworkInfo, password: String) {
        guard let interface = CWWiFiClient.shared().interface() else { return }
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                try interface.associate(to: info.network, password: info.secure ? password : nil)
                DispatchQueue.main.async { self.operationMessage = "Connected to \(info.ssid)"; self.refreshWiFiState() }
            } catch { DispatchQueue.main.async { self.operationMessage = "Could not connect: \(error.localizedDescription)" } }
        }
    }

    func disconnectWiFi() { CWWiFiClient.shared().interface()?.disassociate(); refreshWiFiState() }

    func refreshAudioDevices() {
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDevices, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size) == noErr else { return }
        var ids = [AudioDeviceID](repeating: 0, count: Int(size) / MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &ids) == noErr else { return }
        audioDevices = ids.compactMap { id in
            guard deviceHasOutput(id), let name = deviceName(id) else { return nil }
            return AudioDeviceInfo(id: id, name: name)
        }
        var currentSize = UInt32(MemoryLayout<AudioDeviceID>.size)
        var current: AudioDeviceID = 0
        address.mSelector = kAudioHardwarePropertyDefaultOutputDevice
        if AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &currentSize, &current) == noErr { defaultAudioDevice = current }
        refreshOutputLevel()
    }

    func selectAudioDevice(_ id: AudioDeviceID) {
        var selected = id
        let size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultOutputDevice, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        let status = AudioObjectSetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, size, &selected)
        operationMessage = status == noErr ? "Audio output changed" : "Could not change audio output"
        refreshAudioDevices()
    }

    func refreshOutputLevel() {
        var device = defaultAudioDevice
        if device == 0 {
            var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultOutputDevice, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
            var size = UInt32(MemoryLayout<AudioDeviceID>.size)
            guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &device) == noErr else { return }
            defaultAudioDevice = device
        }
        var levels: [Float32] = []
        for channel in [AudioObjectPropertyElement(0), 1, 2] {
            var volume = Float32(0)
            var size = UInt32(MemoryLayout<Float32>.size)
            var address = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyVolumeScalar, mScope: kAudioDevicePropertyScopeOutput, mElement: channel)
            if AudioObjectHasProperty(device, &address), AudioObjectGetPropertyData(device, &address, 0, nil, &size, &volume) == noErr { levels.append(volume) }
        }
        guard !levels.isEmpty else { return }
        let percent = Double((levels.reduce(0, +) / Float32(levels.count)) * 100)
        if abs(outputVolume - percent) > 0.4 { outputVolume = percent }
    }

    func setOutputVolume(_ value: Double) {
        outputVolume = value
        let script = "set volume output volume \(Int(value))"
        runAppleScript(script)
    }

    func setMuted(_ muted: Bool) { runAppleScript("set volume output muted \(muted ? "true" : "false")") }

    func refreshPowerState() {
        runProcess("/usr/bin/pmset", ["-g", "batt"]) { text in
            let percent = text.range(of: #"\d+%"#, options: .regularExpression).map { String(text[$0]) } ?? "--"
            let level = Int(percent.filter(\.isNumber)) ?? -1
            let lowPower = text.localizedCaseInsensitiveContains("low power mode: 1")
            let charging = text.localizedCaseInsensitiveContains("charging") || text.localizedCaseInsensitiveContains("charged") || text.localizedCaseInsensitiveContains("AC Power")
            DispatchQueue.main.async { self.batteryPercent = percent; self.batteryLevel = level; self.batteryCharging = charging; self.lowPowerMode = lowPower }
        }
        runProcess("/usr/bin/pmset", ["-g", "custom"]) { text in
            let matches = text.components(separatedBy: .newlines).filter { $0.contains("lowpowermode") }
            let lowPower = matches.contains { $0.split(separator: " ").last == "1" }
            DispatchQueue.main.async { self.lowPowerMode = lowPower }
        }
    }

    func setLowPowerMode(_ enabled: Bool) {
        let command = "/usr/bin/pmset -a lowpowermode \(enabled ? 1 : 0)"
        let escaped = command.replacingOccurrences(of: "\"", with: "\\\"")
        let source = "do shell script \"\(escaped)\" with administrator privileges"
        DispatchQueue.global(qos: .userInitiated).async {
            let appleScript = NSAppleScript(source: source); var error: NSDictionary?
            appleScript?.executeAndReturnError(&error)
            DispatchQueue.main.async {
                if let error { self.operationMessage = error[NSAppleScript.errorMessage] as? String ?? "Low Power Mode was not changed" }
                else { self.lowPowerMode = enabled; self.operationMessage = enabled ? "Low Power Mode enabled" : "Low Power Mode disabled" }
                self.refreshPowerState()
            }
        }
    }

    private func runAppleScript(_ source: String) { var error: NSDictionary?; NSAppleScript(source: source)?.executeAndReturnError(&error); if let error { operationMessage = error[NSAppleScript.errorMessage] as? String ?? "Action failed" } }
    private func runProcess(_ path: String, _ arguments: [String], completion: @escaping (String) -> Void) {
        DispatchQueue.global(qos: .utility).async { let process = Process(); let pipe = Pipe(); process.executableURL = URL(fileURLWithPath: path); process.arguments = arguments; process.standardOutput = pipe; do { try process.run(); process.waitUntilExit(); completion(String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? "") } catch { completion("") } }
    }
    private func deviceHasOutput(_ id: AudioDeviceID) -> Bool {
        var address = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyStreamConfiguration, mScope: kAudioDevicePropertyScopeOutput, mElement: kAudioObjectPropertyElementMain); var size: UInt32 = 0
        return AudioObjectGetPropertyDataSize(id, &address, 0, nil, &size) == noErr && size > 0
    }
    private func deviceName(_ id: AudioDeviceID) -> String? {
        var address = AudioObjectPropertyAddress(mSelector: kAudioObjectPropertyName, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var name: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(id, &address, 0, nil, &size, &name) == noErr, let name else { return nil }
        return name.takeUnretainedValue() as String
    }
}
