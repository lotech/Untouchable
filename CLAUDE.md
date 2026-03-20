# CLAUDE.md -- Project context for Claude Code

## Project Overview

Untouchable is a macOS 13+ menu bar app (SwiftUI MenuBarExtra) that enumerates HID pointing devices and allows the user to suppress input from specific ones using IOKit exclusive device seizure. No main window. Runs as LSUIElement.

## Bundle ID

`vision.lotech.Untouchable`

## Key Technical Details

- **Language**: Swift 5.9+, SwiftUI
- **Min target**: macOS 13.0 (Ventura)
- **HID layer**: IOKit -> IOHIDManager for enumeration, IOHIDDeviceOpen with kIOHIDOptionsTypeSeizeDevice for suppression
- **Persistence**: UserDefaults, blocked devices stored as ["vendorID:productID"]
- **Login item**: SMAppService.mainApp
- **Updates**: Sparkle 2.x (SPM dependency, stub only -- not wired yet)

## Architecture

```
Untouchable/
  App/           -- @main entry, AppDelegate
  HID/           -- IOHIDManager wrapper, device model, seizure logic
  UI/            -- MenuBarView, DeviceRowView (SwiftUI)
  Settings/      -- AppSettings (UserDefaults @Published wrapper)
  LoginItem/     -- SMAppService wrapper
  Updater/       -- Sparkle stub
```

## Build & Run

- Xcode: open Untouchable.xcodeproj, Cmd+R
- CLI: `./scripts/build.sh` (interactive menu) or `./scripts/build.sh --build`
- Flags: `--pull`, `--open`, `--build`, `--install`, `--clean`

## Important Patterns

- HIDDeviceManager is an ObservableObject; call `configure(with: AppSettings)` after init to load persisted blocked state
- HIDEventSuppressor tracks seized devices by ID string; always call releaseAll() on termination
- Device matching uses multiple criteria: GD_Mouse, GD_Pointer, Dig_TouchScreen, Dig_TouchPad, Dig_Digitizer
- IOHIDManager callbacks dispatch to main queue before mutating @Published state
- Unmanaged pointers pass `self` to C callbacks -- must use passUnretained/fromOpaque pattern

## Entitlements

- `com.apple.security.device.input-monitoring = YES` (required for HID access)
- App sandbox is OFF (IOKit HID requires unsandboxed access)
- Hardened runtime enabled

## Files to Keep Updated

- **CHANGELOG.md**: Update under [Unreleased] for every feature/fix, move to versioned section on release. Follow Keep a Changelog format.
- **README.md**: Update if features, build steps, or architecture change.

## Conventions

- Pure ASCII in shell scripts (no Unicode ellipsis, em dashes, etc.)
- Swift files use `import IOKit.hid` for HID types
- Console logging uses `print("[Untouchable] ...")` prefix
- No emoji in code or commit messages
