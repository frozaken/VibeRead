# macOS compatibility

The deployment target is macOS 13 Ventura. Keep new code buildable and usable
on that version unless the project explicitly decides to raise the target.

## Guidelines

- Check API availability before using a newer AppKit, AVFoundation, or SwiftUI
  API.
- Wrap macOS 14+ behavior in `if #available(macOS 14.0, *)` and provide a macOS
  13 fallback.
- Prefer established compatibility patterns already in the code. The action
  palette, for example, falls back from SwiftUI `onKeyPress` to an AppKit
  `NSView` keyboard handler on macOS 13.
- Keep pure data models `Sendable` where appropriate and use `@MainActor` only
  for UI-bound services and state.
- Do not change the deployment target or default actor-isolation settings as an
  incidental fix.

## APIs that need care

- `onKeyPress` requires macOS 14.
- Newer `AVCaptureDevice.DeviceType` values require availability checks.
- Two-parameter `onChange` closures require macOS 14.
- `toolbarBackgroundVisibility` requires macOS 15.

Run a full macOS build after touching compatibility paths; a successful compile
against a newer SDK does not prove the macOS 13 fallback is complete.
