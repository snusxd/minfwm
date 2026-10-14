# minfwm Wiki

`minfwm` is an infinite 2D canvas for macOS 14+. It keeps window positions in
virtual coordinates and projects the visible area onto connected displays.
Native macOS Spaces are not implemented.

## Pages

- [[Getting-Started|Getting started]]: build, permissions, and daemon control.
- [[Configuration|Configuration]]: TOML options and defaults.
- [[Architecture|Architecture]]: core/adapter boundary and IPC.
- [[Yabai-Integration|Yabai integration]]: optional extension setup and limits.
- [[Development|Development]]: project layout and focused checks.
- [[Acceptance-macos|macOS acceptance]]: manual-only checks and current status.
- [[AI-Workflow|AI workflow]]: concise repository workflow reference.
- [[Publishing|Publishing]]: automatic GitHub Wiki sync setup.

## Backend and limitations

The Accessibility backend is the baseline and needs no SIP changes. Yabai's
Scripting Addition is optional and version-sensitive. It can provide movement,
layering, and presentation transforms when its handshake advertises compatible
capabilities. Applications can correct window frames after a move; failed
readback falls back to Accessibility and constrained placements are rejected.

The experimental transform extension supports offscreen and above-menu-bar
placement while retaining an application's native frame. Native dragging,
popups, dialogs, and multi-display behavior still require manual acceptance.
