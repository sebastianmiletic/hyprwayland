import SwiftUI
import Foundation
import ApplicationServices
import CoreLocation

struct PermissionsSettingsView: View {
    @ObservedObject var model: AppModel
    @ObservedObject private var notifications: NotificationDaemon
    private var palette: ThemePalette { model.configuration.bar.palette }
    init(model: AppModel) { self.model = model; self.notifications = model.notifications }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            if !model.configuration.hasCompletedOnboarding {
                Label("Step 1 of 2", systemImage: "sparkles").font(.caption.weight(.semibold)).foregroundStyle(Color(hex: palette.accent))
                Text("Choose what Ryft can control").font(.title2.bold())
                Text("Ryft works without optional access. Enable only the desktop features you want. Every permission is requested after you press its button, never silently at launch.").foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            SettingsGroup("System access") {
                permissionRow("Accessibility", detail: "Allows tiling, desktop switching, macOS controls, and reading text you explicitly select for Command+M.", symbol: "accessibility", status: AXIsProcessTrusted() ? "Allowed" : "Not allowed", granted: AXIsProcessTrusted()) {
                    WorkspaceController.requestAccessibility()
                }
                Divider()
                permissionRow("Input Monitoring", detail: "Supports Command+M and any editable global shortcuts that require keyboard monitoring.", symbol: "keyboard", status: CGPreflightListenEventAccess() ? "Allowed" : "Not allowed", granted: CGPreflightListenEventAccess()) {
                    _ = CGRequestListenEventAccess()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { model.statusMessage = "Permission status refreshed" }
                }
                Divider()
                permissionRow("Location for Wi-Fi", detail: "macOS requires Location to reveal nearby network names. Ryft does not store location data.", symbol: "location", status: locationLabel, granted: locationGranted) {
                    model.controls.requestWiFiAccessAndScan()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { model.statusMessage = "Permission status refreshed" }
                }
                Divider()
                permissionRow("Notifications", detail: "Shows Ryft battery warnings. Other apps’ notifications remain private.", symbol: "bell", status: notifications.authorizationStatus, granted: notifications.authorizationStatus == "Enabled") {
                    notifications.requestAuthorization()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { model.statusMessage = "Permission status refreshed" }
                }
                Divider()
                permissionRow("Screen Recording", detail: "Captures a temporary in-memory frame for workspace slides or Command+M when no text is selected. Frames are never saved.", symbol: "rectangle.on.rectangle", status: CGPreflightScreenCaptureAccess() ? "Allowed" : "Not allowed", granted: CGPreflightScreenCaptureAccess()) {
                    let granted = CGRequestScreenCaptureAccess()
                    model.statusMessage = granted ? "Screen Recording enabled" : "Screen Recording permission unchanged"
                }
            }
            if !model.configuration.hasCompletedOnboarding {
                HStack {
                    Button("Skip for now") { model.configuration.hasCompletedOnboarding = true; model.selectedSection = .home }.buttonStyle(SettingsHoverButtonStyle())
                    Spacer()
                    Button("Continue to Quick Start") { model.selectedSection = .guide }.buttonStyle(.borderedProminent)
                }
            }
        }
        .onAppear { notifications.refreshAuthorization() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in model.statusMessage = "Permission status refreshed" }
    }

    private var locationGranted: Bool {
        let status = CLLocationManager().authorizationStatus
        return status == .authorized || status == .authorizedAlways
    }
    private var locationLabel: String {
        switch CLLocationManager().authorizationStatus {
        case .authorized, .authorizedAlways: "Allowed"
        case .denied, .restricted: "Not allowed"
        case .notDetermined: "Not requested"
        @unknown default: "Unknown"
        }
    }

    private func permissionRow(_ title: String, detail: String, symbol: String, status: String, granted: Bool, action: @escaping () -> Void) -> some View {
        HStack(spacing: 13) {
            Image(systemName: symbol).font(.system(size: 16, weight: .semibold)).foregroundStyle(Color(hex: palette.accent)).frame(width: 25)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).fontWeight(.semibold)
                Text(detail).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 16)
            Text(status).font(.caption.weight(.semibold)).foregroundStyle(granted ? Color(hex: palette.success) : .secondary)
            if !granted { Button(status == "Not requested" ? "Enable" : "Open Settings", action: action).buttonStyle(.bordered) }
        }.padding(.vertical, 3)
    }
}

struct QuickStartSettingsView: View {
    @ObservedObject var model: AppModel
    var embedded = false
    private var palette: ThemePalette { model.configuration.bar.palette }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            if !model.configuration.hasCompletedOnboarding && !embedded {
                Label("Step 2 of 2", systemImage: "sparkles").font(.caption.weight(.semibold)).foregroundStyle(Color(hex: palette.accent))
                Text("Your desktop is ready").font(.title2.bold())
                Text("Four controls cover the everyday Ryft workflow. You can replay this guide from Settings at any time.").foregroundStyle(.secondary)
            }
            SettingsGroup("Essentials") {
                guideRow("Open Gemini", detail: "Click the sparkle in the desktop bar. Escape or the close button dismisses the panel.", symbol: "sparkle", shortcut: "") {
                    NotificationCenter.default.post(name: .ryftToggleLeftSidebar, object: nil)
                }
                Divider()
                guideRow("Open Controls", detail: "Click Controls in the desktop bar for Wi-Fi, sound, battery, resources, alerts, and tasks.", symbol: "slider.horizontal.3", shortcut: "") {
                    NotificationCenter.default.post(name: .ryftToggleRightSidebar, object: nil)
                }
                Divider()
                guideRow("Change wallpaper", detail: "Open the far-left wallpaper control. Use arrow keys to choose, then Return to apply.", symbol: "photo.on.rectangle.angled", shortcut: "← → ↩") {
                    NotificationCenter.default.post(name: .ryftShowWallpapers, object: nil)
                }
                Divider()
                guideRow("Shape the bar", detail: "Choose a style, arrange widgets, and see every change on the real desktop immediately.", symbol: "menubar.rectangle", shortcut: "") {
                    model.selectedSection = .waybar
                }
            }
            SettingsGroup("Useful keys") {
                LabeledContent("Answer selected text or visible question", value: "Command + M")
                LabeledContent("Open Finder", value: "Command + E")
                LabeledContent("Close a panel", value: "Escape")
            }
            if !model.configuration.hasCompletedOnboarding {
                HStack {
                    if !embedded { Button("Back") { model.selectedSection = .permissions }.buttonStyle(SettingsHoverButtonStyle()) }
                    Spacer()
                    Button("Finish Setup") { model.configuration.hasCompletedOnboarding = true; model.selectedSection = embedded ? .general : .home }.buttonStyle(.borderedProminent)
                }
            }
        }
    }

    private func guideRow(_ title: String, detail: String, symbol: String, shortcut: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 13) {
                Image(systemName: symbol).font(.system(size: 16, weight: .semibold)).foregroundStyle(Color(hex: palette.accent)).frame(width: 25)
                VStack(alignment: .leading, spacing: 3) { Text(title).fontWeight(.semibold); Text(detail).font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.leading) }
                Spacer(minLength: 16)
                if !shortcut.isEmpty { Text(shortcut).font(.system(.caption, design: .monospaced).weight(.semibold)).padding(.horizontal, 8).padding(.vertical, 5).background(Color.primary.opacity(0.06)).clipShape(RoundedRectangle(cornerRadius: 6)) }
                Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
            }.contentShape(Rectangle()).padding(.vertical, 3)
        }.buttonStyle(SettingsHoverButtonStyle())
    }
}
