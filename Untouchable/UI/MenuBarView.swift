import SwiftUI

/// The SwiftUI content displayed inside the `MenuBarExtra` popover.
struct MenuBarView: View {
    @ObservedObject var deviceManager: HIDDeviceManager
    @ObservedObject var appSettings: AppSettings

    var body: some View {
        // Devices section
        Section("Devices") {
            if deviceManager.devices.isEmpty {
                Text("No pointing devices found")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(deviceManager.devices) { device in
                    DeviceRowView(device: device) {
                        deviceManager.toggleBlocked(for: device)
                        // Read updated state from the manager's array
                        if let updated = deviceManager.devices.first(where: { $0.id == device.id }) {
                            appSettings.setBlocked(updated.isBlocked, forDeviceID: device.id)
                        }
                    }
                }
            }
        }

        Divider()

        // Launch at Login toggle
        Toggle("Launch at Login", isOn: $appSettings.launchAtLogin)
            .onChange(of: appSettings.launchAtLogin) { newValue in
                LoginItemManager.shared.setEnabled(newValue)
            }

        Divider()

        // Sparkle update stub (disabled until wired)
        Button("Check for Updates...") {
            UpdaterManager.shared.checkForUpdates()
        }
        .disabled(true)

        Divider()

        // Quit
        Button("Quit Untouchable") {
            NSApplication.shared.terminate(nil)
        }
        .keyboardShortcut("q")
    }
}
