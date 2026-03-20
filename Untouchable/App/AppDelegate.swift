import Cocoa

/// Application delegate for lifecycle hooks that SwiftUI doesn't cover.
///
/// Used primarily to handle early-launch tasks such as re-applying HID
/// seizures for previously blocked devices.
final class AppDelegate: NSObject, NSApplicationDelegate {

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Future: re-apply seizures for persisted blocked devices
    }

    func applicationWillTerminate(_ notification: Notification) {
        // Future: release all seized devices cleanly
    }
}
