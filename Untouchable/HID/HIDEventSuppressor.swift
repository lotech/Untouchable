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
/// - Retry failed seizures: some HID interfaces (especially on multi-interface
///   touchscreens) may not be ready for exclusive access immediately after
///   enumeration. A delayed retry catches these cases.
final class HIDEventSuppressor {

    /// IOReturn code when TCC (privacy framework) denies device access.
    private static let kIOReturnNotPermitted: IOReturn = -536870174

    /// Maximum number of automatic retries for failed seizures.
    private static let maxRetries = 3

    /// Delay between retry attempts (seconds).
    private static let retryDelay: TimeInterval = 1.0

    /// Tracks which device IDs are currently seized, mapped to their IOHIDDevice refs.
    private var seizedDevices: [String: IOHIDDevice] = [:]

    /// Tracks retry counts for interfaces that failed to seize.
    private var retryCounts: [String: Int] = [:]

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
            retryCounts.removeValue(forKey: device.id)
            logger.info("Seized device: \(device.name, privacy: .private) (\(device.id, privacy: .private))")
        } else {
            let retries = retryCounts[device.id] ?? 0
            if retries < Self.maxRetries {
                retryCounts[device.id] = retries + 1
                let attempt = retries + 1
                logger.info("Seize attempt \(attempt)/\(Self.maxRetries) failed for \(device.name, privacy: .private) interface \(device.id, privacy: .private) (IOReturn \(result)) -- retrying in \(Self.retryDelay)s")
                let deviceCopy = device
                DispatchQueue.main.asyncAfter(deadline: .now() + Self.retryDelay * Double(attempt)) {
                    self.seize(deviceCopy)
                }
            } else {
                retryCounts.removeValue(forKey: device.id)
                if result == Self.kIOReturnNotPermitted {
                    logger.warning("Cannot seize \(device.name, privacy: .private) interface \(device.id, privacy: .private) after \(Self.maxRetries) attempts (TCC denied) -- input from this interface may leak through")
                } else {
                    logger.error("Failed to seize \(device.name, privacy: .private) interface \(device.id, privacy: .private) after \(Self.maxRetries) attempts: IOReturn \(result)")
                }
            }
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

    /// Re-seizes all currently seized devices by closing and re-opening them.
    ///
    /// IOKit can silently lose device seizures after system sleep/wake without
    /// firing any callbacks. This method re-establishes exclusive ownership on
    /// every device the suppressor believes it holds.
    func reseizeAll() {
        for (id, ioDevice) in seizedDevices {
            // Close the (possibly stale) seizure
            IOHIDDeviceRegisterInputValueCallback(ioDevice, nil, nil)
            IOHIDDeviceClose(ioDevice, IOOptionBits(kIOHIDOptionsTypeNone))

            // Re-open with exclusive seizure
            let result = IOHIDDeviceOpen(ioDevice, IOOptionBits(kIOHIDOptionsTypeSeizeDevice))
            if result == kIOReturnSuccess {
                IOHIDDeviceRegisterInputValueCallback(ioDevice, { _, _, _, _ in }, nil)
                logger.info("Re-seized device after wake: \(id, privacy: .private)")
            } else {
                logger.error("Failed to re-seize device after wake: \(id, privacy: .private) IOReturn \(result)")
                seizedDevices.removeValue(forKey: id)
            }
        }
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
