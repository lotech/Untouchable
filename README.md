# Untouchable

A macOS menu bar app that suppresses input from specific HID pointing devices -- solving the ghost-touch / rogue touchscreen problem.

![macOS](https://img.shields.io/badge/macOS-13.0%2B-blue)
![Swift](https://img.shields.io/badge/Swift-5.9-orange)
![License](https://img.shields.io/badge/license-MIT-green)

<!-- ![Screenshot](screenshot.png) -->

## The Problem

External touchscreens (and some built-in ones) can send phantom touch events -- ghost taps, erratic cursor movement, or unwanted clicks. macOS provides no built-in way to disable a specific pointing device without physically unplugging it.

## The Solution

Untouchable sits in your menu bar and lists every HID pointing device connected to your Mac. Toggle any device off and its events are completely suppressed at the IOKit level. No phantom touches, no erratic cursor. Toggle it back on and input resumes instantly.

## Features

- Enumerates all HID pointing devices (mice, trackpads, touchscreens, digitizers)
- Per-device suppression toggle -- seized devices produce zero events system-wide
- Remembers blocked devices across launches (persisted in UserDefaults)
- Auto-reapplies suppression when a previously-blocked device reconnects
- Live connect/disconnect detection
- Runs silently in the menu bar (no Dock icon, no window)
- Launch at Login via `SMAppService`
- Sparkle update framework included (not yet wired)

## Install

### From Release

Download the latest `.dmg` from [Releases](https://github.com/lotech/Untouchable/releases), drag to `/Applications`, and launch.

### From Source

```bash
git clone https://github.com/lotech/Untouchable.git
cd Untouchable
./scripts/build.sh
```

The interactive build menu lets you:

```
+---------------------------------------+
|         Untouchable Builder           |
+---------------------------------------+
|  1)  Pull latest from GitHub          |
|  2)  Open in Xcode                    |
|  3)  Build (Release)                  |
|  4)  Build (Debug)                    |
|  5)  Install to /Applications         |
|  6)  Build + Install (Release)        |
|  7)  Pull + Build + Install           |
|  8)  Launch Untouchable               |
|  9)  Clean build directory            |
|  0)  Quit                             |
+---------------------------------------+
```

Or use flags for CI/scripting: `--pull`, `--open`, `--build`, `--install`, `--clean`.

### Requirements

- macOS 13.0 (Ventura) or later
- Xcode 15+ to build from source
- **Input Monitoring** permission (macOS will prompt on first launch)

## How It Works

1. **Enumerate** -- `IOHIDManager` matches all HID devices with usage pages for mice, pointers, touchscreens, and digitizers.
2. **Seize** -- For blocked devices, `IOHIDDeviceOpen` is called with `kIOHIDOptionsTypeSeizeDevice`, giving Untouchable exclusive ownership. The OS receives zero events from the seized device.
3. **Discard** -- A no-op input callback is registered (required by IOKit) that simply drops all events.
4. **Release** -- `IOHIDDeviceClose` restores normal input instantly.

Blocked devices are stored as `VendorID:ProductID` strings in UserDefaults and re-applied automatically on launch.

## Architecture

```
Untouchable/
  App/
    UntouchableApp.swift          # @main, MenuBarExtra entry point
    AppDelegate.swift             # NSApplicationDelegate lifecycle
  HID/
    HIDDevice.swift               # Model: vendor, product, name, blocked state
    HIDDeviceManager.swift        # IOHIDManager wrapper, enumeration, callbacks
    HIDEventSuppressor.swift      # Seize/release exclusive device ownership
  UI/
    MenuBarView.swift             # SwiftUI menu content
    DeviceRowView.swift           # Per-device toggle row
  Settings/
    AppSettings.swift             # UserDefaults persistence
  LoginItem/
    LoginItemManager.swift        # SMAppService wrapper
  Updater/
    UpdaterManager.swift          # Sparkle stub (inactive)
```

## Privacy & Permissions

Untouchable requires **Input Monitoring** permission to enumerate and seize HID devices. macOS will prompt you the first time the app runs. You can manage this in **System Settings > Privacy & Security > Input Monitoring**.

The app does not:
- Collect or transmit any data
- Log keystrokes or input events
- Require network access
- Phone home in any way

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for guidelines.

## License

[MIT](LICENSE) -- free to use, modify, and distribute.
