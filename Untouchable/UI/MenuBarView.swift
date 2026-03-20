import SwiftUI

/// The SwiftUI content displayed inside the `MenuBarExtra` popover.
struct MenuBarView: View {
    @ObservedObject var deviceManager: HIDDeviceManager
    @ObservedObject var appSettings: AppSettings

    var body: some View {
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

        Divider()

        Button("Quit Untouchable") {
            NSApplication.shared.terminate(nil)
        }
        .keyboardShortcut("q")
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
