import Foundation
import Combine
import IOKit.hid
import os

private let logger = Logger(subsystem: "vision.lotech.Untouchable", category: "HIDDeviceManager")

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

    /// The IOHIDManager used to enumerate and monitor HID devices.
    private var manager: IOHIDManager?

    /// The event suppressor responsible for seizing/releasing individual devices.
    let suppressor = HIDEventSuppressor()

    /// Reference to app settings for checking persisted blocked state.
    private var appSettings: AppSettings?

    // MARK: - Init

    init() {
        setupManager()
    }

    deinit {
        suppressor.releaseAll()
        if let manager = manager {
            IOHIDManagerUnscheduleFromRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
            IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        }
    }

    // MARK: - Setup

    /// Connects to AppSettings so we can restore blocked state on enumeration.
    func configure(with settings: AppSettings) {
        self.appSettings = settings
        refreshDevices()
        reapplyBlockedDevices()
    }

    private func setupManager() {
        manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        guard let manager = manager else { return }

        // Match pointing devices: mice, pointers, touchscreens, digitizers
        let matchingCriteria: [[String: Any]] = [
            [kIOHIDDeviceUsagePageKey: kHIDPage_GenericDesktop,
             kIOHIDDeviceUsageKey: kHIDUsage_GD_Mouse],
            [kIOHIDDeviceUsagePageKey: kHIDPage_GenericDesktop,
             kIOHIDDeviceUsageKey: kHIDUsage_GD_Pointer],
            [kIOHIDDeviceUsagePageKey: kHIDPage_Digitizer,
             kIOHIDDeviceUsageKey: kHIDUsage_Dig_TouchScreen],
            [kIOHIDDeviceUsagePageKey: kHIDPage_Digitizer,
             kIOHIDDeviceUsageKey: kHIDUsage_Dig_TouchPad],
            [kIOHIDDeviceUsagePageKey: kHIDPage_Digitizer,
             kIOHIDDeviceUsageKey: kHIDUsage_Dig_Digitizer],
        ]

        IOHIDManagerSetDeviceMatchingMultiple(manager, matchingCriteria as CFArray)

        // Retain self for the duration of the callback registration.
        // Safe because deinit unschedules the manager before dealloc completes.
        let selfPtr = Unmanaged.passRetained(self).toOpaque()

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

        // Schedule on the main run loop and open
        IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
        IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
    }

    // MARK: - Device callbacks

    private func deviceConnected(_ device: IOHIDDevice) {
        let blocked = appSettings?.isBlocked(deviceID(for: device)) ?? false
        guard let hidDevice = HIDDevice(from: device, isBlocked: blocked) else { return }

        // Avoid duplicates
        if !devices.contains(where: { $0.id == hidDevice.id }) {
            devices.append(hidDevice)
            logger.info("Device connected: \(hidDevice.name, privacy: .private) (\(hidDevice.id, privacy: .private))")
        }

        // Re-apply seizure if this device was previously blocked
        if blocked {
            suppressor.seize(hidDevice)
        }
    }

    private func deviceDisconnected(_ device: IOHIDDevice) {
        let id = deviceID(for: device)
        suppressor.releaseByID(id)
        devices.removeAll(where: { $0.id == id })
        logger.info("Device disconnected: \(id, privacy: .private)")
    }

    private func deviceID(for device: IOHIDDevice) -> String {
        let vid = IOHIDDeviceGetProperty(device, kIOHIDVendorIDKey as CFString) as? Int ?? 0
        let pid = IOHIDDeviceGetProperty(device, kIOHIDProductIDKey as CFString) as? Int ?? 0
        return "\(vid):\(pid)"
    }

    // MARK: - Public API

    /// Refreshes the device list by re-querying the IOHIDManager.
    func refreshDevices() {
        guard let manager = manager else { return }
        guard let deviceSet = IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice> else { return }

        var newDevices: [HIDDevice] = []
        for ioDevice in deviceSet {
            let blocked = appSettings?.isBlocked(deviceID(for: ioDevice)) ?? false
            if let device = HIDDevice(from: ioDevice, isBlocked: blocked) {
                newDevices.append(device)
            }
        }

        devices = newDevices.sorted(by: { $0.name < $1.name })
    }

    /// Re-applies seizure for all persisted blocked devices.
    private func reapplyBlockedDevices() {
        for device in devices where device.isBlocked {
            suppressor.seize(device)
        }
    }

    /// Toggles the blocked state for the given device.
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
