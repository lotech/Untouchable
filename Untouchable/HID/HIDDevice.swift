import Foundation
import IOKit.hid

/// Represents a single HID pointing device discovered by `IOHIDManager`.
///
/// Each device gets a unique `id` from its IOKit registry entry ID, so multiple
/// interfaces on the same physical device (same vendor:product) appear as
/// separate entries. The `persistenceID` (vendorID:productID) is used for
/// UserDefaults storage so blocking one interface blocks all of them.
struct HIDDevice: Identifiable, Hashable {

    /// Unique per-IOHIDDevice instance (IOKit registry entry ID).
    let id: String

    /// Stable identifier for persistence: "vendorID:productID" or "builtin:trackpad".
    var persistenceID: String {
        if isBuiltIn && vendorID == 0 && productID == 0 {
            return "builtin:trackpad"
        }
        return "\(vendorID):\(productID)"
    }

    /// USB Vendor ID.
    let vendorID: Int

    /// USB Product ID.
    let productID: Int

    /// Human-readable device name from the HID descriptor.
    let name: String

    /// Whether the user has chosen to suppress all events from this device.
    var isBlocked: Bool

    /// Whether this device is virtual (software-created, no physical hardware).
    let isVirtual: Bool

    /// HID primary usage page (e.g. GenericDesktop=0x01, Digitizer=0x0D).
    let usagePage: Int

    /// HID primary usage (e.g. Mouse=0x02, TouchScreen=0x04).
    let usage: Int

    /// The underlying `IOHIDDevice` reference.
    var ioHIDDevice: IOHIDDevice?

    /// Whether this is a built-in device (e.g. internal trackpad) that lacks vendor/product IDs.
    let isBuiltIn: Bool

    /// Whether this device is a USB Overdrive VirtualHID proxy.
    /// Overdrive intercepts physical devices at the DriverKit level and forwards
    /// events through synthetic VirtualHID devices, bypassing userspace seizure.
    let isOverdriveVirtual: Bool

    // MARK: - Convenience init from IOHIDDevice

    init?(from device: IOHIDDevice, isBlocked: Bool = false) {
        let vendorID = IOHIDDeviceGetProperty(device, kIOHIDVendorIDKey as CFString) as? Int
        let productID = IOHIDDeviceGetProperty(device, kIOHIDProductIDKey as CFString) as? Int

        let name = IOHIDDeviceGetProperty(device, kIOHIDProductKey as CFString) as? String
            ?? "Unknown Device"

        let entryID = IOHIDDeviceGetProperty(device, kIOHIDUniqueIDKey as CFString) as? Int
            ?? Int(bitPattern: Unmanaged.passUnretained(device).toOpaque())

        // Some Apple Internal interfaces lack the BuiltIn property but can be
        // identified by name. Fall back to name matching so we don't skip them.
        let builtInProp = IOHIDDeviceGetProperty(device, "BuiltIn" as CFString) as? Bool ?? false
        let builtIn = builtInProp || name.hasPrefix("Apple Internal")

        // Devices without vendor/product IDs are accepted only if they are built-in
        // (e.g. Apple Internal Keyboard / Trackpad). External devices without IDs are
        // still skipped because we cannot persist their blocked state reliably.
        if let vid = vendorID, let pid = productID {
            self.vendorID = vid
            self.productID = pid
            self.id = "\(vid):\(pid):\(entryID)"
            self.isBuiltIn = builtIn
        } else if builtIn {
            self.vendorID = 0
            self.productID = 0
            self.id = "builtin:\(entryID)"
            self.isBuiltIn = true
        } else {
            return nil
        }

        self.name = name
        self.isBlocked = isBlocked
        self.ioHIDDevice = device
        self.usagePage = IOHIDDeviceGetProperty(device, kIOHIDPrimaryUsagePageKey as CFString) as? Int ?? 0
        self.usage = IOHIDDeviceGetProperty(device, kIOHIDPrimaryUsageKey as CFString) as? Int ?? 0

        // Detect USB Overdrive VirtualHID proxies. Overdrive's DriverKit extension
        // intercepts physical devices and re-publishes events through synthetic devices
        // that bypass IOKit userspace seizure (kIOHIDOptionsTypeSeizeDevice).
        let isOD = IOHIDDeviceGetProperty(device, "IsOverdriveVirtualHID" as CFString) as? Bool ?? false
        self.isOverdriveVirtual = isOD

        // Detect virtual devices by checking transport or name patterns
        let transport = IOHIDDeviceGetProperty(device, kIOHIDTransportKey as CFString) as? String ?? ""
        let nameLC = name.lowercased()
        self.isVirtual = transport.lowercased() == "virtual"
            || nameLC.contains("virtual")
            || nameLC.contains("karabiner")
            || (transport.isEmpty && !builtIn && (vendorID ?? 0) == 0)
    }

    /// Display name, simplified for built-in devices.
    var displayName: String {
        if isBuiltIn && name.lowercased().contains("keyboard") {
            return "Built-in Trackpad"
        }
        return name
    }

    // MARK: - Hashable

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    static func == (lhs: HIDDevice, rhs: HIDDevice) -> Bool {
        lhs.id == rhs.id
    }
}
