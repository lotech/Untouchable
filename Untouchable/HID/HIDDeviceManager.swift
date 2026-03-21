import Foundation
import Cocoa
import Combine
import IOKit.hid
import os

private let logger = Logger(subsystem: "vision.lotech.Untouchable", category: "HIDDeviceManager")

/// A grouped device representing one physical device (one or more HID interfaces).
struct DeviceGroup: Identifiable {
    /// The persistence key: "vendorID:productID"
    let id: String
    let name: String
    let isVirtual: Bool
    var isBlocked: Bool
}

/// Manages HID device enumeration and publishes the current device list.
final class HIDDeviceManager: ObservableObject {

    // MARK: - Published State

    /// All currently connected HID interfaces (multiple per physical device).
    @Published var devices: [HIDDevice] = []

    /// Physical devices, one row per vendor:product.
    var physicalDeviceGroups: [DeviceGroup] {
        groupedDevices(from: devices.filter { !$0.isVirtual })
    }

    /// Virtual devices, one row per vendor:product.
    var virtualDeviceGroups: [DeviceGroup] {
        groupedDevices(from: devices.filter { $0.isVirtual })
    }

    /// True when USB Overdrive VirtualHID proxies are detected. Overdrive's DriverKit
    /// extension intercepts physical HID devices and forwards events through synthetic
    /// devices, bypassing userspace seizure. Blocking will not work until Overdrive is
    /// removed or disabled.
    var overdriveDetected: Bool {
        devices.contains { $0.isOverdriveVirtual }
    }

    private func groupedDevices(from list: [HIDDevice]) -> [DeviceGroup] {
        var groups: [String: DeviceGroup] = [:]
        for device in list {
            let pid = device.persistenceID
            if groups[pid] == nil {
                groups[pid] = DeviceGroup(
                    id: pid,
                    name: device.displayName,
                    isVirtual: device.isVirtual,
                    isBlocked: device.isBlocked
                )
            }
        }
        return groups.values.sorted { $0.name < $1.name }
    }

    // MARK: - Private

    private var manager: IOHIDManager?
    let suppressor = HIDEventSuppressor()
    private var appSettings: AppSettings

    /// Retains `self` for the C callback context pointer; released in `deinit`.
    private var retainedSelf: Unmanaged<HIDDeviceManager>?

    /// True during the initial enumeration burst. Seizures are skipped entirely
    /// (not attempted) until the deferred seize timer fires, because IOKit
    /// reports success during enumeration but does not enforce the seizure.
    private var deferringInitialSeizures = false

    // MARK: - Init

    init(settings: AppSettings) {
        self.appSettings = settings
        setupManager()
        observeSystemWake()

        // Skip the initial seize in deviceConnected entirely. Instead, wait for
        // IOKit to fully settle, then seize blocked devices. The initial seize
        // always reports success but never takes effect. Using a flag so
        // hot-plugged devices after launch still get seized immediately.
        self.deferringInitialSeizures = true

        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) { [weak self] in
            guard let self = self else { return }
            self.deferringInitialSeizures = false
            let blocked = self.devices.filter { $0.isBlocked }
            guard !blocked.isEmpty else { return }
            logger.notice("Deferred seize: seizing \(blocked.count) blocked device(s)")
            for i in self.devices.indices where self.devices[i].isBlocked {
                self.suppressor.seize(self.devices[i])
            }
        }
    }

    deinit {
        suppressor.releaseAll()
        if let manager = manager {
            IOHIDManagerUnscheduleFromRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
            IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        }
        retainedSelf?.release()
    }

    /// Re-seizes all blocked devices after the system wakes from sleep.
    ///
    /// IOKit can silently lose device seizures when hardware powers down
    /// during sleep. No callbacks fire to inform the app, so we must
    /// proactively re-establish exclusive ownership on wake.
    private func observeSystemWake() {
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self = self else { return }
            logger.notice("System wake detected -- re-seizing blocked devices")
            self.suppressor.reseizeAll()
            self.refreshDevices()
            self.reapplyBlockedDevices()
        }
    }

    private func setupManager() {
        manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        guard let manager = manager else { return }

        // Match mice, pointers, and ALL digitizer-page devices.
        // Touchscreens often expose multiple HID interfaces with different
        // digitizer usages (TouchScreen, Pen, MultiplePointDigitizer,
        // DeviceConfiguration, etc.). Matching the entire digitizer usage page
        // ensures we discover -- and can seize -- every interface, preventing
        // touch input from leaking through unmatched interfaces.
        let matchingCriteria: [[String: Any]] = [
            [kIOHIDDeviceUsagePageKey: kHIDPage_GenericDesktop,
             kIOHIDDeviceUsageKey: kHIDUsage_GD_Mouse],
            [kIOHIDDeviceUsagePageKey: kHIDPage_GenericDesktop,
             kIOHIDDeviceUsageKey: kHIDUsage_GD_Pointer],
            [kIOHIDDeviceUsagePageKey: kHIDPage_Digitizer],
        ]

        IOHIDManagerSetDeviceMatchingMultiple(manager, matchingCriteria as CFArray)

        let unmanaged = Unmanaged.passRetained(self)
        retainedSelf = unmanaged
        let selfPtr = unmanaged.toOpaque()

        IOHIDManagerRegisterDeviceMatchingCallback(manager, { context, _, _, device in
            guard let context = context else { return }
            let mgr = Unmanaged<HIDDeviceManager>.fromOpaque(context).takeUnretainedValue()
            DispatchQueue.main.async {
                mgr.deviceConnected(device)
            }
        }, selfPtr)

        IOHIDManagerRegisterDeviceRemovalCallback(manager, { context, _, _, device in
            guard let context = context else { return }
            let mgr = Unmanaged<HIDDeviceManager>.fromOpaque(context).takeUnretainedValue()
            DispatchQueue.main.async {
                mgr.deviceDisconnected(device)
            }
        }, selfPtr)

        IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
        IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
    }

    // MARK: - Device callbacks

    private func deviceConnected(_ device: IOHIDDevice) {
        let persistID = persistenceID(for: device)
        let blocked = appSettings.isBlocked(persistID)
        guard let hidDevice = HIDDevice(from: device, isBlocked: blocked) else {
            let rawName = IOHIDDeviceGetProperty(device, kIOHIDProductKey as CFString) as? String ?? "(no name)"
            let usagePage = IOHIDDeviceGetProperty(device, kIOHIDPrimaryUsagePageKey as CFString) as? Int ?? -1
            let usage = IOHIDDeviceGetProperty(device, kIOHIDPrimaryUsageKey as CFString) as? Int ?? -1
            logger.error("Skipped HID interface (no vendor/product ID, not built-in): name=\(rawName, privacy: .public) usagePage=\(usagePage) usage=\(usage)")
            return
        }

        // Deduplicate by unique instance ID
        if !devices.contains(where: { $0.id == hidDevice.id }) {
            devices.append(hidDevice)
            logger.notice("Device connected: \(hidDevice.name, privacy: .public) (\(hidDevice.id, privacy: .public)) usagePage=\(hidDevice.usagePage) usage=\(hidDevice.usage) virtual=\(hidDevice.isVirtual) blocked=\(blocked)")

            if hidDevice.isOverdriveVirtual {
                logger.warning("USB Overdrive VirtualHID detected: \(hidDevice.name, privacy: .public) (\(hidDevice.id, privacy: .public)) -- Overdrive intercepts HID at the driver level, bypassing userspace seizure")
            }
        }

        if blocked && !deferringInitialSeizures {
            suppressor.seize(hidDevice)
        }
    }

    private func deviceDisconnected(_ device: IOHIDDevice) {
        // Match by unique ID rather than object reference -- the IOHIDDevice
        // pointer in the removal callback may differ from the one stored at
        // connect time (e.g. after sleep/wake or USB hub re-enumeration).
        let vid = IOHIDDeviceGetProperty(device, kIOHIDVendorIDKey as CFString) as? Int
        let pid = IOHIDDeviceGetProperty(device, kIOHIDProductIDKey as CFString) as? Int
        let builtInProp = IOHIDDeviceGetProperty(device, "BuiltIn" as CFString) as? Bool ?? false
        let name = IOHIDDeviceGetProperty(device, kIOHIDProductKey as CFString) as? String ?? ""
        let builtIn = builtInProp || name.hasPrefix("Apple Internal")
        let entryID = IOHIDDeviceGetProperty(device, kIOHIDUniqueIDKey as CFString) as? Int
            ?? Int(bitPattern: Unmanaged.passUnretained(device).toOpaque())
        let disconnectedID: String
        if builtIn && vid == nil && pid == nil {
            disconnectedID = "builtin:\(entryID)"
        } else {
            disconnectedID = "\(vid ?? 0):\(pid ?? 0):\(entryID)"
        }

        if let index = devices.firstIndex(where: { $0.id == disconnectedID }) {
            let removed = devices.remove(at: index)
            suppressor.releaseByID(removed.id)
            logger.notice("Device disconnected: \(removed.name, privacy: .public) (\(removed.id, privacy: .public))")
        } else {
            logger.error("Removal callback for unknown device id=\(disconnectedID, privacy: .public)")
        }
    }

    private func persistenceID(for device: IOHIDDevice) -> String {
        let vid = IOHIDDeviceGetProperty(device, kIOHIDVendorIDKey as CFString) as? Int
        let pid = IOHIDDeviceGetProperty(device, kIOHIDProductIDKey as CFString) as? Int
        let builtInProp = IOHIDDeviceGetProperty(device, "BuiltIn" as CFString) as? Bool ?? false
        let name = IOHIDDeviceGetProperty(device, kIOHIDProductKey as CFString) as? String ?? ""
        let builtIn = builtInProp || name.hasPrefix("Apple Internal")
        if builtIn && vid == nil && pid == nil {
            return "builtin:trackpad"
        }
        return "\(vid ?? 0):\(pid ?? 0)"
    }

    // MARK: - Public API

    /// Replaces the device list from a fresh IOHIDManager query.
    /// Merges with existing entries to preserve IOHIDDevice references from callbacks.
    func refreshDevices() {
        guard let manager = manager else { return }
        guard let deviceSet = IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice> else { return }

        // Build a set of IDs we already track
        var existingByID: [String: HIDDevice] = [:]
        for d in devices { existingByID[d.id] = d }

        var merged: [HIDDevice] = []
        for ioDevice in deviceSet {
            let blocked = appSettings.isBlocked(persistenceID(for: ioDevice))
            if let device = HIDDevice(from: ioDevice, isBlocked: blocked) {
                // Keep existing entry if we already have it (preserves ioHIDDevice ref)
                if let existing = existingByID[device.id] {
                    var updated = existing
                    updated.isBlocked = blocked
                    merged.append(updated)
                } else {
                    merged.append(device)
                }
            }
        }

        devices = merged
    }

    private func reapplyBlockedDevices() {
        for device in devices where device.isBlocked {
            suppressor.seize(device)
        }
    }

    /// Toggles the blocked state for all interfaces sharing the given persistenceID.
    func toggleBlocked(forPersistenceID persistenceID: String) {
        // Determine new state from the first matching device
        guard let first = devices.first(where: { $0.persistenceID == persistenceID }) else { return }
        let newBlocked = !first.isBlocked

        for i in devices.indices where devices[i].persistenceID == persistenceID {
            devices[i].isBlocked = newBlocked
            if newBlocked {
                suppressor.seize(devices[i])
            } else {
                suppressor.release(devices[i])
            }
        }
    }
}
