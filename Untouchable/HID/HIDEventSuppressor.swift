import Foundation

/// Seizes and releases HID devices to suppress their events system-wide.
///
/// ## Strategy
/// - Call `IOHIDDeviceOpen` with `kIOHIDOptionsTypeSeizeDevice` to gain
///   exclusive ownership. The OS receives no events from a seized device.
/// - Register a no-op input callback (required by IOKit even when seizing).
/// - Call `IOHIDDeviceClose` to release and restore normal input.
///
/// This class does **not** own the device list — it operates on individual
/// ``HIDDevice`` values handed to it by ``HIDDeviceManager``.
final class HIDEventSuppressor {

    // MARK: - Public API

    /// Seizes the given device, suppressing all of its HID events.
    ///
    /// - Parameter device: The device to seize. Must have a valid `ioHIDDevice`.
    func seize(_ device: HIDDevice) {
        // TODO: Guard that device.ioHIDDevice is non-nil.
        //       Cast to IOHIDDevice.
        //       Call IOHIDDeviceOpen(device, kIOHIDOptionsTypeSeizeDevice).
        //       Register a discard callback via IOHIDDeviceRegisterInputValueCallback.
    }

    /// Releases a previously seized device, restoring normal input.
    ///
    /// - Parameter device: The device to release.
    func release(_ device: HIDDevice) {
        // TODO: Guard that device.ioHIDDevice is non-nil.
        //       Call IOHIDDeviceClose(device).
    }

    /// Releases all currently seized devices. Called on app termination.
    func releaseAll() {
        // TODO: Iterate tracked seized devices and close each one.
    }
}
