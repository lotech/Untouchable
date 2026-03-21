import SwiftUI

/// The SwiftUI content displayed inside the `MenuBarExtra` popover.
struct MenuBarView: View {
    @ObservedObject var deviceManager: HIDDeviceManager
    @ObservedObject var appSettings: AppSettings

    var body: some View {
        if deviceManager.suppressor.tccDenied {
            Section {
                Text("Input Monitoring Denied")
                    .foregroundStyle(.red)
                Button("Open Input Monitoring Settings...") {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent") {
                        NSWorkspace.shared.open(url)
                    }
                }
                Button("Details...") {
                    showTCCAlert()
                }
            }
        }

        if deviceManager.overdriveDetected {
            Section {
                Button("USB Overdrive Conflict") {
                    showOverdriveAlert()
                }
            }
        }

        Section("Devices") {
            let physical = deviceManager.physicalDeviceGroups
            if physical.isEmpty {
                Text("No physical devices found")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(physical) { group in
                    deviceToggle(for: group)
                }
            }
        }

        let virtual = deviceManager.virtualDeviceGroups
        if !virtual.isEmpty {
            Menu("Other Devices (\(virtual.count))") {
                ForEach(virtual) { group in
                    deviceToggle(for: group)
                }
            }
        }

        Divider()

        Toggle("Launch at Login", isOn: $appSettings.launchAtLogin)
            .onChange(of: appSettings.launchAtLogin) { newValue in
                LoginItemManager.shared.setEnabled(newValue)
            }

        Divider()

        Button("About Untouchable") {
            AboutWindow.show()
        }

        Button("Check for Updates...") {
            UpdaterManager.shared.checkForUpdates()
        }
        .disabled(true)

        Button("Reset Permissions & Relaunch") {
            resetTCCAndRelaunch()
        }

        Divider()

        Button("Quit Untouchable") {
            NSApplication.shared.terminate(nil)
        }
        .keyboardShortcut("q")
    }

    private func showTCCAlert() {
        let names = deviceManager.suppressor.tccDeniedDeviceNames.sorted().joined(separator: ", ")
        let alert = NSAlert()
        alert.messageText = "Input Monitoring Permission Denied"
        alert.informativeText = "Untouchable cannot block input from: \(names).\n\nRemove and re-add Untouchable in System Settings > Privacy & Security > Input Monitoring, then relaunch."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Open Settings")
        alert.addButton(withTitle: "OK")
        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn {
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent") {
                NSWorkspace.shared.open(url)
            }
        }
    }

    private func showOverdriveAlert() {
        let alert = NSAlert()
        alert.messageText = "USB Overdrive Detected"
        alert.informativeText = "USB Overdrive intercepts HID devices at the driver level, which prevents Untouchable from blocking input.\n\nUninstall USB Overdrive and restart your Mac for Untouchable to work correctly."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "OK")
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }

    private func resetTCCAndRelaunch() {
        let bundleID = Bundle.main.bundleIdentifier ?? "vision.lotech.Untouchable"
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/tccutil")
        process.arguments = ["reset", "ListenEvent", bundleID]
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            let alert = NSAlert()
            alert.messageText = "Failed to Reset Permissions"
            alert.informativeText = "tccutil failed: \(error.localizedDescription)"
            alert.alertStyle = .warning
            alert.addButton(withTitle: "OK")
            NSApp.activate(ignoringOtherApps: true)
            alert.runModal()
            return
        }

        // Relaunch ourselves
        guard let appURL = Bundle.main.bundleURL as URL? else { return }
        let config = NSWorkspace.OpenConfiguration()
        config.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: appURL, configuration: config) { _, _ in
            DispatchQueue.main.async {
                NSApplication.shared.terminate(nil)
            }
        }
    }

    @ViewBuilder
    private func deviceToggle(for group: DeviceGroup) -> some View {
        Toggle(isOn: Binding(
            get: {
                deviceManager.devices.first(where: { $0.persistenceID == group.id })?.isBlocked ?? false
            },
            set: { newValue in
                deviceManager.toggleBlocked(forPersistenceID: group.id)
                appSettings.setBlocked(newValue, forDeviceID: group.id)
            }
        )) {
            Text(group.name)
        }
    }
}
