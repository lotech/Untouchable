import SwiftUI

enum AboutWindow {
    private static var windowController: NSWindowController?

    static func show() {
        if let existing = windowController {
            existing.window?.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let window = NSWindow(
            contentRect: .zero,
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "About Untouchable"
        window.contentView = NSHostingView(rootView: AboutView())
        window.center()
        window.isReleasedWhenClosed = false

        let controller = NSWindowController(window: window)
        windowController = controller
        controller.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

struct AboutView: View {
    private let repoURL = URL(string: "https://github.com/lotech/Untouchable")!

    private var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
    }

    private var buildNumber: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
    }

    private var copyright: String {
        Bundle.main.object(forInfoDictionaryKey: "NSHumanReadableCopyright") as? String ?? ""
    }

    var body: some View {
        VStack(spacing: 12) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 96, height: 96)

            Text("Untouchable")
                .font(.title2)
                .fontWeight(.semibold)

            Text("Version \(appVersion) (\(buildNumber))")
                .font(.callout)
                .foregroundStyle(.secondary)

            Text(copyright)
                .font(.caption)
                .foregroundStyle(.tertiary)

            Button("View on GitHub") {
                NSWorkspace.shared.open(repoURL)
            }
            .buttonStyle(.link)
            .font(.callout)
        }
        .padding(24)
        .frame(width: 280)
    }
}
