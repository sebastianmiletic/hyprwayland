import AppKit
import Combine
import CoreAudio
import CoreLocation
import CoreWLAN
import IOKit.ps
import ApplicationServices

struct WiFiNetworkInfo: Identifiable, Hashable {
    let id: String
    let ssid: String
    let signal: Int
    let secure: Bool
    let known: Bool
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
    @Published var highPowerMode = false
    @Published private(set) var supportsHighPowerMode = false
    @Published var batteryPercent = "--"
    @Published var batteryLevel = -1
    @Published var batteryCharging = false
    @Published var operationMessage = ""

    // Core Location must be created after NSApplication has finished launching.
    // Constructing it during SwiftUI's early model initialization gives
    // locationd an empty bundle identity, so macOS cannot persist its decision.
    private lazy var locationManager: CLLocationManager = {
        let manager = CLLocationManager()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyThreeKilometers
        manager.pausesLocationUpdatesAutomatically = true
        return manager
    }()
    private var levelTimer: Timer?
    private var powerTimer: Timer?
    private var powerSource: CFRunLoopSource?
    private var observers: [NSObjectProtocol] = []
    private var workspaceObservers: [NSObjectProtocol] = []

    override init() {
        super.init()
        refreshPowerCapabilities()
        refreshAll()
        levelTimer = Timer.scheduledTimer(withTimeInterval: 0.35, repeats: true) { [weak self] _ in self?.refreshOutputLevel() }
        powerTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in self?.refreshPowerState() }
        let context = Unmanaged.passUnretained(self).toOpaque()
        powerSource = IOPSNotificationCreateRunLoopSource({ context in
            guard let context else { return }
            Unmanaged<SystemControlService>.fromOpaque(context).takeUnretainedValue().refreshPowerState()
        }, context)?.takeRetainedValue()
        if let powerSource { CFRunLoopAddSource(CFRunLoopGetMain(), powerSource, .commonModes) }
        observers.append(NotificationCenter.default.addObserver(forName: Notification.Name.NSProcessInfoPowerStateDidChange, object: nil, queue: .main) { [weak self] _ in self?.refreshPowerState() })
        workspaceObservers.append(NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in self?.refreshAll() })
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
            guard let self, self.locationManager.authorizationStatus == .authorized || self.locationManager.authorizationStatus == .authorizedAlways else { return }
            self.scanWiFi()
        }
    }
    deinit {
        levelTimer?.invalidate(); powerTimer?.invalidate()
        if let powerSource { CFRunLoopRemoveSource(CFRunLoopGetMain(), powerSource, .commonModes) }
        observers.forEach(NotificationCenter.default.removeObserver)
        workspaceObservers.forEach(NSWorkspace.shared.notificationCenter.removeObserver)
    }

    func refreshAll() {
        refreshWiFiState(); refreshAudioDevices(); refreshPowerState()
    }

    func prepareWiFiMenu() {
        operationMessage = ""
        refreshWiFiState()
        if wifiNetworks.isEmpty { requestWiFiAccessAndScan() }
    }

    func prepareSoundMenu() {
        operationMessage = ""
        refreshAudioDevices()
    }

    func requestWiFiAccessAndScan() {
        switch locationManager.authorizationStatus {
        case .authorized, .authorizedAlways:
            // CoreWLAN can continue returning redacted/empty scan results until
            // locationd has delivered at least one update to this process.
            locationManager.startUpdatingLocation()
            scanWiFi()
        case .notDetermined:
            // Retain and actively use the same manager through authorization.
            // This prevents System Settings from treating the request as an
            // abandoned transient client and immediately reverting its toggle.
            locationManager.requestWhenInUseAuthorization()
            locationManager.startUpdatingLocation()
        case .denied, .restricted: operationMessage = "Allow Location in Privacy & Security to list nearby Wi-Fi networks."
        @unknown default: operationMessage = "Nearby Wi-Fi networks are unavailable."
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        if manager.authorizationStatus == .authorized || manager.authorizationStatus == .authorizedAlways {
            manager.startUpdatingLocation()
            scanWiFi()
            DispatchQueue.main.asyncAfter(deadline: .now() + 5) { manager.stopUpdatingLocation() }
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        manager.stopUpdatingLocation()
        scanWiFi()
    }
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        if (error as? CLError)?.code != .denied { operationMessage = "Location check: \(error.localizedDescription)" }
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

    func scanWiFi() { scanWiFi(attempt: 0) }

    private func scanWiFi(attempt: Int) {
        guard let interface = CWWiFiClient.shared().interface(), interface.powerOn() else {
            wifiNetworks = []; scanningWiFi = false; operationMessage = wifiEnabled ? "Wi-Fi interface is unavailable." : "Wi-Fi is off."
            return
        }
        scanningWiFi = true
        if attempt == 0 { operationMessage = "Scanning nearby networks…" }
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let results = try interface.scanForNetworks(withSSID: nil)
                let profiles = interface.configuration()?.networkProfiles.array as? [CWNetworkProfile] ?? []
                let knownSSIDs = Set(profiles.compactMap(\.ssid))
                let mapped = results.compactMap { network -> WiFiNetworkInfo? in
                    guard let ssid = network.ssid, !ssid.isEmpty else { return nil }
                    return WiFiNetworkInfo(id: "\(ssid)-\(network.bssid ?? "")", ssid: ssid, signal: network.rssiValue, secure: !network.supportsSecurity(.none), known: knownSSIDs.contains(ssid), network: network)
                }.sorted { $0.signal > $1.signal }
                var seen = Set<String>()
                let unique = mapped.filter { seen.insert($0.ssid).inserted }
                DispatchQueue.main.async {
                    if unique.isEmpty, attempt < 2 {
                        DispatchQueue.main.asyncAfter(deadline: .now() + Double(attempt + 1)) { self.scanWiFi(attempt: attempt + 1) }
                    } else {
                        self.wifiNetworks = unique
                        self.scanningWiFi = false
                        self.operationMessage = unique.isEmpty ? "No nearby networks found. Toggle Location access off and on, then refresh." : ""
                        self.refreshWiFiState()
                    }
                }
            } catch {
                DispatchQueue.main.async {
                    if attempt < 2 {
                        DispatchQueue.main.asyncAfter(deadline: .now() + Double(attempt + 1)) { self.scanWiFi(attempt: attempt + 1) }
                    } else {
                        self.operationMessage = "Wi-Fi scan: \(error.localizedDescription)"
                        self.scanningWiFi = false
                    }
                }
            }
        }
    }

    func connect(to info: WiFiNetworkInfo, password: String = "") {
        guard let interface = CWWiFiClient.shared().interface() else { return }
        operationMessage = "Connecting to \(info.ssid)…"
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                try interface.associate(to: info.network, password: (info.secure && !info.known) ? password : nil)
                DispatchQueue.main.async { self.operationMessage = "Connected to \(info.ssid)"; self.refreshWiFiState() }
            } catch { DispatchQueue.main.async {
                let message = error.localizedDescription
                self.operationMessage = message.localizedCaseInsensitiveContains("cancel") ? "" : "Could not connect: \(message)"
            } }
        }
    }

    func connectHiddenNetwork(ssid: String, password: String) {
        let ssid = ssid.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !ssid.isEmpty, let interface = CWWiFiClient.shared().interface() else { operationMessage = "Enter a network name."; return }
        operationMessage = "Finding \(ssid)…"
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                guard let network = try interface.scanForNetworks(withName: ssid).max(by: { $0.rssiValue < $1.rssiValue }) else {
                    DispatchQueue.main.async { self.operationMessage = "Network not found." }; return
                }
                try interface.associate(to: network, password: password.isEmpty ? nil : password)
                DispatchQueue.main.async { self.operationMessage = "Connected to \(ssid)"; self.refreshWiFiState(); self.scanWiFi() }
            } catch { DispatchQueue.main.async { self.operationMessage = "Could not join: \(error.localizedDescription)" } }
        }
    }

    func disconnectWiFi() { CWWiFiClient.shared().interface()?.disassociate(); refreshWiFiState(); operationMessage = "Disconnected" }

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
        let lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] else {
            lowPowerMode = lowPower
            return
        }
        for source in sources {
            guard let description = IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue() as? [String: Any],
                  (description[kIOPSTypeKey] as? String) == (kIOPSInternalBatteryType as String),
                  (description[kIOPSIsPresentKey] as? Bool) != false else { continue }
            let current = (description[kIOPSCurrentCapacityKey] as? NSNumber)?.doubleValue ?? 0
            let maximum = max((description[kIOPSMaxCapacityKey] as? NSNumber)?.doubleValue ?? 100, 1)
            let level = max(0, min(100, Int((current / maximum * 100).rounded())))
            let charging = (description[kIOPSIsChargingKey] as? Bool) == true
            if batteryLevel != level { batteryLevel = level; batteryPercent = "\(level)%" }
            if batteryCharging != charging { batteryCharging = charging }
            if lowPowerMode != lowPower { lowPowerMode = lowPower }
            return
        }
        lowPowerMode = lowPower
    }

    func setLowPowerMode(_ enabled: Bool) {
        guard enabled != lowPowerMode else { return }
        operationMessage = enabled ? "Enabling Low Power Mode…" : "Disabling Low Power Mode…"
        runPasswordlessPowerCommand(["-b", "lowpowermode", enabled ? "1" : "0"]) { [weak self] success in
            guard let self else { return }
            self.refreshPowerState()
            self.operationMessage = success && self.lowPowerMode == enabled
                ? (enabled ? "Low Power Mode enabled" : "Low Power Mode disabled")
                : "macOS denied the passwordless power change. Ryft did not open Settings or request authentication."
        }
    }

    func setHighPowerMode(_ enabled: Bool) {
        guard supportsHighPowerMode else { return }
        operationMessage = enabled ? "Enabling High Power Mode…" : "Returning to Automatic…"
        runPasswordlessPowerCommand(["-a", "highpowermode", enabled ? "1" : "0"]) { [weak self] success in
            guard let self else { return }
            self.highPowerMode = success && enabled
            self.operationMessage = success ? (enabled ? "High Power Mode enabled" : "Automatic power mode enabled") : "macOS denied the passwordless power change."
        }
    }

    private func refreshPowerCapabilities() {
        let task = Process(); let pipe = Pipe()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/pmset"); task.arguments = ["-g", "custom"]; task.standardOutput = pipe; task.standardError = FileHandle.nullDevice
        do { try task.run(); task.waitUntilExit(); let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""; supportsHighPowerMode = output.contains("highpowermode"); highPowerMode = output.range(of: #"highpowermode\s+1"#, options: .regularExpression) != nil } catch { }
    }

    private func runPasswordlessPowerCommand(_ arguments: [String], completion: @escaping (Bool) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            let task = Process(); task.executableURL = URL(fileURLWithPath: "/usr/bin/pmset"); task.arguments = arguments
            task.standardOutput = FileHandle.nullDevice; task.standardError = FileHandle.nullDevice
            do { try task.run(); task.waitUntilExit(); DispatchQueue.main.async { completion(task.terminationStatus == 0) } }
            catch { DispatchQueue.main.async { completion(false) } }
        }
    }

    private func setLowPowerModeThroughSystemSettings(_ enabled: Bool, retries: Int) {
        guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.systempreferences").first else {
            retryLowPowerMode(enabled, retries: retries); return
        }
        let root = AXUIElementCreateApplication(app.processIdentifier)
        let elements = accessibilityDescendants(of: root)
        let popup = elements.first { element in
            let role: String? = axAttribute(element, kAXRoleAttribute as CFString)
            guard role == (kAXPopUpButtonRole as String) || role == "AXMenuButton" else { return false }
            let value: String = axAttribute(element, kAXValueAttribute as CFString) ?? ""
            let title: String = axAttribute(element, kAXTitleAttribute as CFString) ?? ""
            let description: String = axAttribute(element, kAXDescriptionAttribute as CFString) ?? ""
            let combined = "\(value) \(title) \(description)".lowercased()
            return combined.contains("low power") || combined == "never  " || combined.contains("only on battery") || combined == "always  "
        }
        guard let popup else { retryLowPowerMode(enabled, retries: retries); return }

        guard AXUIElementPerformAction(popup, kAXPressAction as CFString) == .success else {
            retryLowPowerMode(enabled, retries: retries); return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) { [weak self] in
            guard let self else { return }
            let menuItems = self.accessibilityDescendants(of: root)
            let desired = menuItems.first { element in
                let role: String? = self.axAttribute(element, kAXRoleAttribute as CFString)
                let title: String = self.axAttribute(element, kAXTitleAttribute as CFString) ?? ""
                guard role == (kAXMenuItemRole as String) else { return false }
                return enabled ? title.localizedCaseInsensitiveContains("Always") : title.localizedCaseInsensitiveContains("Never")
            }
            if let desired, AXUIElementPerformAction(desired, kAXPressAction as CFString) == .success {
                app.hide()
                self.finishLowPowerModeChange(enabled)
            }
            else { self.retryLowPowerMode(enabled, retries: retries) }
        }
    }

    private func retryLowPowerMode(_ enabled: Bool, retries: Int) {
        guard retries > 0 else {
            operationMessage = "Battery Settings is open. Choose Low Power Mode there; Ryft will never request your password."
            refreshPowerState(); return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in self?.setLowPowerModeThroughSystemSettings(enabled, retries: retries - 1) }
    }

    private func finishLowPowerModeChange(_ enabled: Bool) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { [weak self] in
            guard let self else { return }
            self.refreshPowerState()
            if self.lowPowerMode == enabled { self.operationMessage = enabled ? "Low Power Mode enabled without authentication" : "Low Power Mode disabled without authentication" }
            else { self.operationMessage = "Battery Settings is open. Choose Low Power Mode there; Ryft will never request your password." }
        }
    }

    private func accessibilityDescendants(of root: AXUIElement, limit: Int = 1200) -> [AXUIElement] {
        var result: [AXUIElement] = []; var queue: [AXUIElement] = [root]; var index = 0
        while index < queue.count, result.count < limit {
            let element = queue[index]; index += 1; result.append(element)
            if let children: [AXUIElement] = axAttribute(element, kAXChildrenAttribute as CFString) { queue.append(contentsOf: children) }
        }
        return result
    }

    private func axAttribute<T>(_ element: AXUIElement, _ attribute: CFString) -> T? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute, &value) == .success else { return nil }
        return value as? T
    }

    private func runAppleScript(_ source: String) {
        var error: NSDictionary?; NSAppleScript(source: source)?.executeAndReturnError(&error)
        if let error {
            let message = error[NSAppleScript.errorMessage] as? String ?? "Action failed"
            operationMessage = message.localizedCaseInsensitiveContains("cancel") ? "" : message
        }
    }
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
