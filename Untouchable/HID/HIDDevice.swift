import Foundation
import IOKit.hid

/// Represents a single HID pointing device discovered by `IOHIDManager`.
///
/// Each device is uniquely identified by its `vendorID:productID` pair.
/// The `isBlocked` flag indicates whether the app is currently seizing
/// (suppressing) input from this device.
struct HIDDevice: Identifiable, Hashable {

    /// Stable identifier derived from vendor and product IDs.
    var id: String { "\(vendorID):\(productID)" }

    /// USB Vendor ID.
    let vendorID: Int

    /// USB Product ID.
    let productID: Int

    /// Human-readable device name from the HID descriptor (e.g. "Magic Trackpad").
    let name: String

    /// Whether the user has chosen to suppress all events from this device.
    var isBlocked: Bool

    /// The underlying `IOHIDDevice` reference. Nil when the device is no longer connected.
    var ioHIDDevice: IOHIDDevice?

    // MARK: - Convenience init from IOHIDDevice

    /// Creates an `HIDDevice` from a raw `IOHIDDevice` reference.
    init?(from device: IOHIDDevice, isBlocked: Bool = false) {
        guard let vendorID = IOHIDDeviceGetProperty(device, kIOHIDVendorIDKey as CFString) as? Int,
              let productID = IOHIDDeviceGetProperty(device, kIOHIDProductIDKey as CFString) as? Int else {
            return nil
        }

        let name = IOHIDDeviceGetProperty(device, kIOHIDProductKey as CFString) as? String
            ?? "Unknown Device"

        self.vendorID = vendorID
        self.productID = productID
        self.name = name
        self.isBlocked = isBlocked
        self.ioHIDDevice = device
    }

    // MARK: - Hashable

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    static func == (lhs: HIDDevice, rhs: HIDDevice) -> Bool {
        lhs.id == rhs.id
    }
}
