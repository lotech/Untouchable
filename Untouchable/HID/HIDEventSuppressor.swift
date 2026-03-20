import Foundation
import IOKit.hid

/// Seizes and releases HID devices to suppress their events system-wide.
///
/// ## Strategy
/// - Call `IOHIDDeviceOpen` with `kIOHIDOptionsTypeSeizeDevice` to gain
///   exclusive ownership. The OS receives no events from a seized device.
/// - Register a no-op input callback (required by IOKit even when seizing).
/// - Call `IOHIDDeviceClose` to release and restore normal input.
final class HIDEventSuppressor {

    /// Tracks which device IDs are currently seized, mapped to their IOHIDDevice refs.
    private var seizedDevices: [String: IOHIDDevice] = [:]

    // MARK: - Public API

    /// Seizes the given device, suppressing all of its HID events.
    func seize(_ device: HIDDevice) {
        guard let ioDevice = device.ioHIDDevice else {
            print("[Untouchable] Cannot seize \(device.name): no IOHIDDevice ref")
            return
        }

        // Already seized
        if seizedDevices[device.id] != nil { return }

        let result = IOHIDDeviceOpen(ioDevice, IOOptionBits(kIOHIDOptionsTypeSeizeDevice))
        if result == kIOReturnSuccess {
            // Register a no-op callback -- required by IOKit even when seizing
            IOHIDDeviceRegisterInputValueCallback(ioDevice, { _, _, _ in
                // Discard all events
            }, nil)

            seizedDevices[device.id] = ioDevice
            print("[Untouchable] Seized device: \(device.name) (\(device.id))")
        } else {
            print("[Untouchable] Failed to seize \(device.name): IOReturn \(result)")
        }
    }

    /// Releases a previously seized device, restoring normal input.
    func release(_ device: HIDDevice) {
        releaseByID(device.id)
    }

    /// Releases a seized device by its ID string.
    func releaseByID(_ deviceID: String) {
        guard let ioDevice = seizedDevices.removeValue(forKey: deviceID) else { return }

        IOHIDDeviceRegisterInputValueCallback(ioDevice, nil, nil)
        IOHIDDeviceClose(ioDevice, IOOptionBits(kIOHIDOptionsTypeNone))
        print("[Untouchable] Released device: \(deviceID)")
    }

    /// Releases all currently seized devices. Called on app termination.
    func releaseAll() {
        for (id, ioDevice) in seizedDevices {
            IOHIDDeviceRegisterInputValueCallback(ioDevice, nil, nil)
            IOHIDDeviceClose(ioDevice, IOOptionBits(kIOHIDOptionsTypeNone))
            print("[Untouchable] Released device: \(id)")
        }
        seizedDevices.removeAll()
    }
}
