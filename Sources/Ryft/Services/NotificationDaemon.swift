import AppKit
import Combine
import UserNotifications

struct RyftNotification: Identifiable {
    let id = UUID()
    let title: String
    let message: String
    let date = Date()
}

/// Emits Ryft-owned system notifications without repeatedly asking for
/// authorization. macOS does not expose another app's Notification Center
/// history, so Messages and other app alerts remain owned by the system.
final class NotificationDaemon: NSObject, ObservableObject, UNUserNotificationCenterDelegate {
    @Published private(set) var recent: [RyftNotification] = []
    @Published private(set) var authorizationStatus = "Checking…"

    private let controls: SystemControlService
    private var cancellables = Set<AnyCancellable>()
    private var notifiedThresholds = Set<Int>()
    private let center = UNUserNotificationCenter.current()

    init(controls: SystemControlService) {
        self.controls = controls
        super.init()
        center.delegate = self
        configureAuthorization()
        controls.$batteryLevel.removeDuplicates().sink { [weak self] in self?.processBattery(level: $0) }.store(in: &cancellables)
    }

    func refreshAuthorization() { configureAuthorization() }

    func requestAuthorization() {
        center.requestAuthorization(options: [.alert, .sound]) { [weak self] _, _ in self?.configureAuthorization() }
    }

    private func configureAuthorization() {
        center.getNotificationSettings { [weak self] settings in
            guard let self else { return }
            DispatchQueue.main.async { self.authorizationStatus = self.label(settings.authorizationStatus) }
            // Permission prompts are never triggered at launch. macOS owns this
            // decision; Ryft only uses an existing grant.
        }
    }

    private func processBattery(level: Int) {
        guard level >= 0 else { return }
        if level > 25 { notifiedThresholds.removeAll() }
        let threshold = [5, 10, 20].first { level <= $0 }
        guard let threshold, !controls.batteryCharging, !notifiedThresholds.contains(threshold) else { return }
        notifiedThresholds.insert(threshold)
        let urgent = threshold <= 10
        post(title: urgent ? "Battery critically low" : "Battery low", message: "Battery is at \(level)%. Connect your Mac to power.", sound: urgent)
    }

    func post(title: String, message: String, sound: Bool = true) {
        let item = RyftNotification(title: title, message: message)
        DispatchQueue.main.async {
            self.recent.insert(item, at: 0)
            if self.recent.count > 20 { self.recent.removeLast(self.recent.count - 20) }
        }
        center.getNotificationSettings { [weak self] settings in
            guard let self, settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else { return }
            let content = UNMutableNotificationContent(); content.title = title; content.body = message
            if sound { content.sound = .default }
            self.center.add(UNNotificationRequest(identifier: item.id.uuidString, content: content, trigger: nil))
        }
    }

    private func label(_ status: UNAuthorizationStatus) -> String {
        switch status { case .authorized, .provisional, .ephemeral: "Enabled"; case .denied: "Disabled"; case .notDetermined: "Not requested"; @unknown default: "Unknown" }
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }
}
