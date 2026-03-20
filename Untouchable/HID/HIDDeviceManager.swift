import Foundation
import Combine
import IOKit.hid
import os

private let logger = Logger(subsystem: "vision.lotech.Untouchable", category: "HIDDeviceManager")

/// Manages HID device enumeration and publishes the current device list.
final class HIDDeviceManager: ObservableObject {

    // MARK: - Published State

    /// All currently connected HID pointing devices.
    @Published var devices: [HIDDevice] = []

    /// Physical (non-virtual) devices, sorted by name.
    var physicalDevices: [HIDDevice] {
        devices.filter { !$0.isVirtual }.sorted { $0.name < $1.name }
    }

    /// Virtual/software devices, sorted by name.
    var virtualDevices: [HIDDevice] {
        devices.filter { $0.isVirtual }.sorted { $0.name < $1.name }
    }

    // MARK: - Private

    private var manager: IOHIDManager?
    let suppressor = HIDEventSuppressor()
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

    func configure(with settings: AppSettings) {
        self.appSettings = settings
        refreshDevices()
        reapplyBlockedDevices()
    }

    private func setupManager() {
        manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        guard let manager = manager else { return }

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

        IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
        IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
    }

    // MARK: - Device callbacks

    private func deviceConnected(_ device: IOHIDDevice) {
        let persistID = persistenceID(for: device)
        let blocked = appSettings?.isBlocked(persistID) ?? false
        guard let hidDevice = HIDDevice(from: device, isBlocked: blocked) else { return }

        if !devices.contains(where: { $0.id == hidDevice.id }) {
            devices.append(hidDevice)
            logger.info("Device connected: \(hidDevice.name, privacy: .private) (\(hidDevice.id, privacy: .private)) virtual=\(hidDevice.isVirtual)")
        }

        if blocked {
            suppressor.seize(hidDevice)
        }
    }

    private func deviceDisconnected(_ device: IOHIDDevice) {
        // Find by IOHIDDevice reference since the device is being removed
        if let index = devices.firstIndex(where: { $0.ioHIDDevice == device }) {
            let removed = devices.remove(at: index)
            suppressor.releaseByID(removed.id)
            logger.info("Device disconnected: \(removed.name, privacy: .private) (\(removed.id, privacy: .private))")
        }
    }

    private func persistenceID(for device: IOHIDDevice) -> String {
        let vid = IOHIDDeviceGetProperty(device, kIOHIDVendorIDKey as CFString) as? Int ?? 0
        let pid = IOHIDDeviceGetProperty(device, kIOHIDProductIDKey as CFString) as? Int ?? 0
        return "\(vid):\(pid)"
    }

    // MARK: - Public API

    func refreshDevices() {
        guard let manager = manager else { return }
        guard let deviceSet = IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice> else { return }

        var newDevices: [HIDDevice] = []
        for ioDevice in deviceSet {
            let blocked = appSettings?.isBlocked(persistenceID(for: ioDevice)) ?? false
            if let device = HIDDevice(from: ioDevice, isBlocked: blocked) {
                newDevices.append(device)
            }
        }

        devices = newDevices
    }

    private func reapplyBlockedDevices() {
        for device in devices where device.isBlocked {
            suppressor.seize(device)
        }
    }

    /// Toggles the blocked state for a device. Blocks/unblocks ALL interfaces
    /// sharing the same persistenceID (vendor:product).
    func toggleBlocked(for device: HIDDevice) {
        let newBlocked: Bool
        if let index = devices.firstIndex(where: { $0.id == device.id }) {
            newBlocked = !devices[index].isBlocked
        } else {
            return
        }

        // Apply to all interfaces with the same vendor:product
        for i in devices.indices where devices[i].persistenceID == device.persistenceID {
            devices[i].isBlocked = newBlocked
            if newBlocked {
                suppressor.seize(devices[i])
            } else {
                suppressor.release(devices[i])
            }
        }
    }
}
