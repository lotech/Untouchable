import Foundation
import IOKit.hid
import os

private let logger = Logger(subsystem: "vision.lotech.Untouchable", category: "HIDEventSuppressor")

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
            logger.warning("Cannot seize \(device.name, privacy: .private): no IOHIDDevice ref")
            return
        }

        // Already seized
        if seizedDevices[device.id] != nil { return }

        let result = IOHIDDeviceOpen(ioDevice, IOOptionBits(kIOHIDOptionsTypeSeizeDevice))
        if result == kIOReturnSuccess {
            // Register a no-op callback -- required by IOKit even when seizing
            IOHIDDeviceRegisterInputValueCallback(ioDevice, { _, _, _, _ in
                // Discard all events
            }, nil)

            seizedDevices[device.id] = ioDevice
            logger.info("Seized device: \(device.name, privacy: .private) (\(device.id, privacy: .private))")
        } else if result == -536870174 {
            // TCC denied -- expected for some HID interfaces that macOS restricts.
            // The primary touch interface is usually seized successfully.
            logger.debug("TCC denied seize for \(device.name, privacy: .private) interface \(device.id, privacy: .private) -- expected for secondary interfaces")
        } else {
            logger.error("Failed to seize \(device.name, privacy: .private): IOReturn \(result)")
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
        logger.info("Released device: \(deviceID, privacy: .private)")
    }

    /// Releases all currently seized devices. Called on app termination.
    func releaseAll() {
        for (id, ioDevice) in seizedDevices {
            IOHIDDeviceRegisterInputValueCallback(ioDevice, nil, nil)
            IOHIDDeviceClose(ioDevice, IOOptionBits(kIOHIDOptionsTypeNone))
            logger.info("Released device: \(id, privacy: .private)")
        }
        seizedDevices.removeAll()
    }
}
