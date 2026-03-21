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

    /// Stable identifier for persistence: "vendorID:productID".
    var persistenceID: String { "\(vendorID):\(productID)" }

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

    // MARK: - Convenience init from IOHIDDevice

    init?(from device: IOHIDDevice, isBlocked: Bool = false) {
        guard let vendorID = IOHIDDeviceGetProperty(device, kIOHIDVendorIDKey as CFString) as? Int,
              let productID = IOHIDDeviceGetProperty(device, kIOHIDProductIDKey as CFString) as? Int else {
            return nil
        }

        let name = IOHIDDeviceGetProperty(device, kIOHIDProductKey as CFString) as? String
            ?? "Unknown Device"

        // Use the IOKit registry entry ID for a truly unique per-instance identifier
        let entryID = IOHIDDeviceGetProperty(device, kIOHIDUniqueIDKey as CFString) as? Int
            ?? Int(bitPattern: Unmanaged.passUnretained(device).toOpaque())
        self.id = "\(vendorID):\(productID):\(entryID)"

        self.vendorID = vendorID
        self.productID = productID
        self.name = name
        self.isBlocked = isBlocked
        self.ioHIDDevice = device
        self.usagePage = IOHIDDeviceGetProperty(device, kIOHIDPrimaryUsagePageKey as CFString) as? Int ?? 0
        self.usage = IOHIDDeviceGetProperty(device, kIOHIDPrimaryUsageKey as CFString) as? Int ?? 0

        // Detect virtual devices by checking transport or name patterns
        let transport = IOHIDDeviceGetProperty(device, kIOHIDTransportKey as CFString) as? String ?? ""
        let isBuiltIn = IOHIDDeviceGetProperty(device, "BuiltIn" as CFString) as? Bool ?? false
        let nameLC = name.lowercased()
        self.isVirtual = transport.lowercased() == "virtual"
            || nameLC.contains("virtual")
            || nameLC.contains("karabiner")
            || (transport.isEmpty && !isBuiltIn && vendorID == 0)
    }

    /// Display name with disambiguation for duplicate device names.
    var displayName: String {
        name
    }

    // MARK: - Hashable

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    static func == (lhs: HIDDevice, rhs: HIDDevice) -> Bool {
        lhs.id == rhs.id
    }
}
