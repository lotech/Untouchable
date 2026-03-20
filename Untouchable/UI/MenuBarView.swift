import SwiftUI

/// The SwiftUI content displayed inside the `MenuBarExtra` popover.
struct MenuBarView: View {
    @ObservedObject var deviceManager: HIDDeviceManager
    @ObservedObject var appSettings: AppSettings

    var body: some View {
        // Physical devices section
        Section("Devices") {
            let physical = deviceManager.physicalDevices
            if physical.isEmpty {
                Text("No physical devices found")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(physical) { device in
                    deviceToggleButton(for: device)
                }
            }
        }

        // Virtual devices in a submenu (already deduplicated by manager)
        let virtual = deviceManager.virtualDevices
        if !virtual.isEmpty {
            Menu("Other Devices (\(virtual.count))") {
                ForEach(virtual) { device in
                    deviceToggleButton(for: device)
                }
            }
        }

        Divider()

        Toggle("Launch at Login", isOn: $appSettings.launchAtLogin)
            .onChange(of: appSettings.launchAtLogin) { newValue in
                LoginItemManager.shared.setEnabled(newValue)
            }

        Divider()

        Button("Check for Updates...") {
            UpdaterManager.shared.checkForUpdates()
        }
        .disabled(true)

        Divider()

        Button("Quit Untouchable") {
            NSApplication.shared.terminate(nil)
        }
        .keyboardShortcut("q")
    }

    @ViewBuilder
    private func deviceToggleButton(for device: HIDDevice) -> some View {
        // Use a Toggle so macOS renders a native checkmark
        Toggle(isOn: Binding(
            get: {
                deviceManager.devices.first(where: { $0.id == device.id })?.isBlocked ?? false
            },
            set: { _ in
                deviceManager.toggleBlocked(for: device)
                appSettings.setBlocked(
                    deviceManager.devices.first(where: { $0.id == device.id })?.isBlocked ?? false,
                    forDeviceID: device.persistenceID
                )
            }
        )) {
            Text(device.displayName)
        }
    }
}
