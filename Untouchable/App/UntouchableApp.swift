import SwiftUI

/// Main entry point for Untouchable.
///
/// Uses `MenuBarExtra` (macOS 13+) to present a menu bar-only interface.
/// The app has no main window -- `LSUIElement` is set in Info.plist to hide
/// the Dock icon and app switcher entry.
@main
struct UntouchableApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    /// Shared device manager that enumerates and manages HID devices.
    @StateObject private var deviceManager = HIDDeviceManager()

    /// Shared settings for persisted user preferences.
    @StateObject private var appSettings = AppSettings()

    var body: some Scene {
        MenuBarExtra("Untouchable", image: "MenuBarIcon") {
            MenuBarView(deviceManager: deviceManager, appSettings: appSettings)
                .onAppear {
                    deviceManager.configure(with: appSettings)
                }
        }
    }
}
