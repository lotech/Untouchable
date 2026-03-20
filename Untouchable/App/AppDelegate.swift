import Cocoa

/// Application delegate for lifecycle hooks that SwiftUI doesn't cover.
final class AppDelegate: NSObject, NSApplicationDelegate {

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Device enumeration is handled by HIDDeviceManager on init.
        // Seizures are re-applied when configure(with:) is called from the UI.
    }

    func applicationWillTerminate(_ notification: Notification) {
        // Release is handled by HIDDeviceManager.deinit -> suppressor.releaseAll()
    }
}
