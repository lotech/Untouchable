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
final class HIDEventSuppressor: ObservableObject {

    /// IOReturn code when TCC (privacy framework) denies device access.
    private static let kIOReturnNotPermitted: IOReturn = -536870174

    /// Maximum number of automatic retries for failed seizures (transient errors only).
    private static let maxRetries = 3

    /// Delay between retry attempts (seconds).
    private static let retryDelay: TimeInterval = 1.0

    /// Tracks which device IDs are currently seized, mapped to their IOHIDDevice refs.
    private var seizedDevices: [String: IOHIDDevice] = [:]

    /// Tracks retry counts for interfaces that failed to seize.
    private var retryCounts: [String: Int] = [:]

    /// Pending retry work items, keyed by device ID. Cancelled on disconnect.
    private var pendingRetries: [String: DispatchWorkItem] = [:]

    /// Device IDs where seizure was permanently denied (TCC). Not retried until
    /// the device disconnects and reconnects (which implies a new TCC check).
    private var tccDeniedIDs: Set<String> = []

    /// Set to `true` when at least one device seizure fails due to TCC denial.
    /// The UI observes this to prompt the user to re-grant Input Monitoring.
    @Published var tccDenied: Bool = false

    /// Device names that failed due to TCC denial (for display in the alert).
    @Published var tccDeniedDeviceNames: Set<String> = []

    // MARK: - Public API

    /// Seizes the given device, suppressing all of its HID events.
    func seize(_ device: HIDDevice) {
        guard let ioDevice = device.ioHIDDevice else {
            logger.warning("Cannot seize \(device.name, privacy: .public): no IOHIDDevice ref")
            return
        }

        // Already seized or permanently denied for this interface
        if seizedDevices[device.id] != nil { return }
        if tccDeniedIDs.contains(device.id) { return }

        // Close any existing non-exclusive open (e.g. from IOHIDManagerOpen)
        // before opening with exclusive seizure. IOKit does not upgrade an
        // existing non-exclusive open to exclusive; the close-then-reopen
        // cycle is what makes the manual toggle path work.
        IOHIDDeviceClose(ioDevice, IOOptionBits(kIOHIDOptionsTypeNone))

        let result = IOHIDDeviceOpen(ioDevice, IOOptionBits(kIOHIDOptionsTypeSeizeDevice))
        if result == kIOReturnSuccess {
            // Register a no-op callback -- required by IOKit even when seizing
            IOHIDDeviceRegisterInputValueCallback(ioDevice, { _, _, _, _ in
                // Discard all events
            }, nil)

            seizedDevices[device.id] = ioDevice
            retryCounts.removeValue(forKey: device.id)
            pendingRetries.removeValue(forKey: device.id)
            tccDeniedDeviceNames.remove(device.name)
            if tccDeniedDeviceNames.isEmpty {
                tccDenied = false
            }
            logger.notice("Seized device: \(device.name, privacy: .public) (\(device.id, privacy: .public))")
        } else if result == Self.kIOReturnNotPermitted {
            // TCC (Input Monitoring) denial or another process holds exclusive seizure.
            // Single-instance enforcement eliminates the competing-process case, so this
            // is almost certainly TCC. Don't retry -- TCC status won't change mid-session.
            retryCounts.removeValue(forKey: device.id)
            pendingRetries.removeValue(forKey: device.id)?.cancel()
            tccDeniedIDs.insert(device.id)
            tccDenied = true
            tccDeniedDeviceNames.insert(device.name)
            logger.warning("Cannot seize \(device.name, privacy: .public) interface \(device.id, privacy: .public) (TCC denied) -- input from this interface will leak through. Grant Input Monitoring permission in System Settings and relaunch.")
        } else {
            // Transient failure (e.g. device not ready after enumeration) -- retry
            let retries = retryCounts[device.id] ?? 0
            if retries < Self.maxRetries {
                retryCounts[device.id] = retries + 1
                let attempt = retries + 1
                let delay = Self.retryDelay * Double(attempt)
                logger.notice("Seize attempt \(attempt)/\(Self.maxRetries) failed for \(device.name, privacy: .public) interface \(device.id, privacy: .public) (IOReturn \(result)) -- retrying in \(delay)s")
                let deviceCopy = device
                let workItem = DispatchWorkItem { [weak self] in
                    self?.seize(deviceCopy)
                }
                pendingRetries[device.id] = workItem
                DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)
            } else {
                retryCounts.removeValue(forKey: device.id)
                pendingRetries.removeValue(forKey: device.id)
                logger.error("Failed to seize \(device.name, privacy: .public) interface \(device.id, privacy: .public) after \(Self.maxRetries) attempts: IOReturn \(result)")
            }
        }
    }

    /// Releases a previously seized device, restoring normal input.
    func release(_ device: HIDDevice) {
        releaseByID(device.id)
    }

    /// Releases a seized device by its ID string. Also cancels any pending
    /// retries and clears TCC denial state so a reconnect gets a fresh attempt.
    func releaseByID(_ deviceID: String) {
        // Cancel any pending retry for this interface
        pendingRetries.removeValue(forKey: deviceID)?.cancel()
        retryCounts.removeValue(forKey: deviceID)
        tccDeniedIDs.remove(deviceID)

        guard let ioDevice = seizedDevices.removeValue(forKey: deviceID) else { return }

        IOHIDDeviceRegisterInputValueCallback(ioDevice, nil, nil)
        IOHIDDeviceClose(ioDevice, IOOptionBits(kIOHIDOptionsTypeNone))
        logger.notice("Released device: \(deviceID, privacy: .public)")
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
                logger.notice("Re-seized device after wake: \(id, privacy: .public)")
            } else {
                logger.error("Failed to re-seize device after wake: \(id, privacy: .public) IOReturn \(result)")
                seizedDevices.removeValue(forKey: id)
            }
        }
    }

    /// Releases all currently seized devices. Called on app termination.
    func releaseAll() {
        for (_, workItem) in pendingRetries { workItem.cancel() }
        pendingRetries.removeAll()
        retryCounts.removeAll()
        tccDeniedIDs.removeAll()

        for (id, ioDevice) in seizedDevices {
            IOHIDDeviceRegisterInputValueCallback(ioDevice, nil, nil)
            IOHIDDeviceClose(ioDevice, IOOptionBits(kIOHIDOptionsTypeNone))
            logger.notice("Released device: \(id, privacy: .public)")
        }
        seizedDevices.removeAll()
    }
}
