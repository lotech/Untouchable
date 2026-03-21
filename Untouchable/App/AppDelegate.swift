import Cocoa
import os

private let logger = Logger(subsystem: "vision.lotech.Untouchable", category: "AppDelegate")

/// Application delegate for lifecycle hooks that SwiftUI doesn't cover.
final class AppDelegate: NSObject, NSApplicationDelegate {

    func applicationDidFinishLaunching(_ notification: Notification) {
        terminateOtherInstances()
    }

    func applicationWillTerminate(_ notification: Notification) {
        // Release is handled by HIDDeviceManager.deinit -> suppressor.releaseAll()
    }

    /// Terminates any other running instances of Untouchable.
    ///
    /// Multiple instances compete for exclusive IOHIDDevice seizure, causing
    /// ghost input to leak through whichever interface the other process holds.
    /// This ensures only one instance owns all HID seizures at any time.
    private func terminateOtherInstances() {
        let myPID = ProcessInfo.processInfo.processIdentifier
        let others = NSRunningApplication.runningApplications(
            withBundleIdentifier: Bundle.main.bundleIdentifier ?? "vision.lotech.Untouchable"
        ).filter { $0.processIdentifier != myPID }

        for app in others {
            logger.notice("Terminating other instance: PID \(app.processIdentifier)")
            app.terminate()
        }

        // If any were found, give them a moment to release seizures
        if !others.isEmpty {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                for app in others where !app.isTerminated {
                    logger.warning("Force-terminating stale instance: PID \(app.processIdentifier)")
                    app.forceTerminate()
                }
            }
        }
    }
}
