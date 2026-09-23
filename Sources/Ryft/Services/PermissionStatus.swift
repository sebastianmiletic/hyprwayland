import ApplicationServices
import CoreGraphics
import CoreLocation

struct RyftPermissionStatus {
    static var accessibilityGranted: Bool { AXIsProcessTrusted() }
    static var inputMonitoringGranted: Bool { CGPreflightListenEventAccess() }
    static var screenRecordingGranted: Bool { CGPreflightScreenCaptureAccess() }

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
