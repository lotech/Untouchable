import Foundation
import Combine

/// Manages HID device enumeration and publishes the current device list.
///
/// Wraps `IOHIDManager` to:
/// 1. Match pointing devices (mice, trackpads, touchscreens, digitizers).
/// 2. Observe device connect/disconnect events.
/// 3. Publish an up-to-date `[HIDDevice]` array for the UI to bind to.
///
/// Device seizure (suppression) is handled by ``HIDEventSuppressor``.
final class HIDDeviceManager: ObservableObject {

    // MARK: - Published State

    /// All currently connected HID pointing devices.
    @Published var devices: [HIDDevice] = []

    // MARK: - Private

    /// The event suppressor responsible for seizing/releasing individual devices.
    let suppressor = HIDEventSuppressor()

    // MARK: - Init

    init() {
        // TODO: Create IOHIDManager, set matching dictionaries for
        //       kHIDUsage_GD_Mouse, kHIDUsage_GD_Pointer, kHIDUsage_Digitizer_*,
        //       register connect/disconnect callbacks, schedule on RunLoop.main,
        //       and call IOHIDManagerOpen.
    }

    // MARK: - Public API

    /// Refreshes the device list by re-querying the IOHIDManager.
    func refreshDevices() {
        // TODO: Copy matching devices from the manager, map to HIDDevice models,
        //       merge blocked state from AppSettings, and update `devices`.
    }

    /// Toggles the blocked state for the given device.
    ///
    /// - Parameter device: The device to block or unblock.
    func toggleBlocked(for device: HIDDevice) {
        guard let index = devices.firstIndex(where: { $0.id == device.id }) else { return }
        devices[index].isBlocked.toggle()

        if devices[index].isBlocked {
            suppressor.seize(devices[index])
        } else {
            suppressor.release(devices[index])
        }
    }
}
