import Foundation

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

    /// The underlying `IOHIDDevice` reference. Nil when the device is no longer
    /// connected. Not included in Hashable/Equatable conformance.
    var ioHIDDevice: Any?

    // MARK: - Hashable

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    static func == (lhs: HIDDevice, rhs: HIDDevice) -> Bool {
        lhs.id == rhs.id
    }
}
