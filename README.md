# Untouchable

A macOS menu bar app that lets you suppress input from specific HID pointing devices — solving the ghost-touch / rogue touchscreen problem.

<!-- ![Screenshot](screenshot.png) -->

## Features

- Enumerates all HID pointing devices (mice, trackpads, touchscreens, digitizers)
- Toggle suppression per device — seized devices produce zero events system-wide
- Remembers blocked devices across launches
- Runs silently in the menu bar (no Dock icon)
- Optional Launch at Login via `SMAppService`
- Built-in update support via Sparkle (coming soon)

## Requirements

- macOS 13.0 (Ventura) or later
- Xcode 15+ to build from source
- Input Monitoring permission (granted on first launch)

## Install

### From Source

```bash
git clone https://github.com/AlohaHealth/Untouchable.git
cd Untouchable
open Untouchable.xcodeproj
```

Build and run with **Cmd+R** in Xcode. Grant Input Monitoring when prompted.

### Releases

Check the [Releases](https://github.com/AlohaHealth/Untouchable/releases) page for pre-built `.dmg` files.

## How It Works

Untouchable uses `IOHIDManager` to enumerate pointing devices, then calls `IOHIDDeviceOpen` with `kIOHIDOptionsTypeSeizeDevice` on any device the user marks as blocked. This gives the app exclusive ownership of the device's HID event stream, starving the rest of the OS — effectively suppressing all input from that device without disabling it at the driver level.

When a device is unblocked, `IOHIDDeviceClose` releases the seizure and normal input resumes immediately.

Blocked device identifiers (`VendorID:ProductID`) are persisted in `UserDefaults` and re-applied automatically on launch.

## License

[MIT](LICENSE)
