import SwiftUI

/// A single row in the device list showing the device name and a toggle
/// to suppress (block) or allow its input.
struct DeviceRowView: View {
    let device: HIDDevice
    let onToggle: () -> Void

    var body: some View {
        Button {
            onToggle()
        } label: {
            HStack {
                Image(systemName: device.isBlocked ? "circle.fill" : "circle")
                    .foregroundStyle(device.isBlocked ? .red : .green)
                Text(device.name)
                Spacer()
                Text(device.isBlocked ? "Suppressed" : "Active")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
