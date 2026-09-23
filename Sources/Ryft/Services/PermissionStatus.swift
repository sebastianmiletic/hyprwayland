import ApplicationServices
import CoreGraphics
import CoreLocation
import AppKit
import Combine

struct RyftPermissionStatus {
    static var accessibilityGranted: Bool { AXIsProcessTrusted() }
    static var inputMonitoringGranted: Bool { CGPreflightListenEventAccess() }
    static var screenRecordingGranted: Bool { CGPreflightScreenCaptureAccess() || UserDefaults.standard.bool(forKey: "RyftVerifiedScreenRecording") }

    static var locationGranted: Bool {
        let status = CLLocationManager().authorizationStatus
        return status == .authorized || status == .authorizedAlways
    }

    static func notificationsGranted(status: String) -> Bool { status == "Enabled" }

    static func missingCount(notificationStatus: String) -> Int {
        [
            accessibilityGranted,
            inputMonitoringGranted,
            locationGranted,
            notificationsGranted(status: notificationStatus),
            screenRecordingGranted
        ].filter { !$0 }.count
    }
}

/// Keeps permission-dependent UI and services synchronized after the user
/// returns from System Settings. TCC changes do not emit a public notification,
/// so Ryft refreshes on activation and at a low-frequency fallback interval.
final class RyftPermissionMonitor: ObservableObject {
    static let shared = RyftPermissionMonitor()

    @Published private(set) var accessibilityGranted = AXIsProcessTrusted()
    @Published private(set) var inputMonitoringGranted = CGPreflightListenEventAccess()
    @Published private(set) var screenRecordingGranted = RyftPermissionStatus.screenRecordingGranted
    @Published private(set) var locationGranted = RyftPermissionStatus.locationGranted

    private var timer: Timer?
    private var activationObserver: NSObjectProtocol?

    private init() {
        activationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in self?.refresh() }
        timer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in self?.refresh() }
    }

    deinit {
        timer?.invalidate()
        if let activationObserver { NotificationCenter.default.removeObserver(activationObserver) }
    }

    func refresh() {
        let accessibility = AXIsProcessTrusted()
        let input = CGPreflightListenEventAccess()
        let recording = RyftPermissionStatus.screenRecordingGranted
        let location = RyftPermissionStatus.locationGranted
        if accessibilityGranted != accessibility { accessibilityGranted = accessibility }
        if inputMonitoringGranted != input { inputMonitoringGranted = input }
        if screenRecordingGranted != recording { screenRecordingGranted = recording }
        if locationGranted != location { locationGranted = location }
    }

    func missingCount(notificationStatus: String) -> Int {
        [
            accessibilityGranted,
            inputMonitoringGranted,
            locationGranted,
            RyftPermissionStatus.notificationsGranted(status: notificationStatus),
            screenRecordingGranted
        ].filter { !$0 }.count
    }
}
