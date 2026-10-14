# minfwm Wiki

`minfwm` is an infinite 2D canvas for macOS 14+. It keeps window positions in
virtual coordinates and projects the visible area onto connected displays.
Native macOS Spaces are not implemented.

## Pages

- [Getting started](https://github.com/snusxd/minfwm/wiki/Getting-Started): build, permissions, and daemon control.
- [Configuration](https://github.com/snusxd/minfwm/wiki/Configuration): TOML options and defaults.
- [Architecture](https://github.com/snusxd/minfwm/wiki/Architecture): core/adapter boundary and IPC.
- [Yabai integration](https://github.com/snusxd/minfwm/wiki/Yabai-Integration): required extension setup and limits.
- [Development](https://github.com/snusxd/minfwm/wiki/Development): project layout and focused checks.
- [macOS acceptance](https://github.com/snusxd/minfwm/wiki/Acceptance-macos#macos-acceptance): manual-only checks and current status.
- [AI workflow](https://github.com/snusxd/minfwm/wiki/AI-Workflow): concise repository workflow reference.
- [Publishing](https://github.com/snusxd/minfwm/wiki/Publishing): automatic GitHub Wiki sync setup.

## Backend and limitations

The Yabai Scripting Addition is required. Its compatible transform and pinned
level capabilities allow windows to appear above the menu bar. Applications
can correct window frames after a move; constrained placements are rejected.

The experimental transform extension supports offscreen and above-menu-bar
placement while retaining an application's native frame. Native dragging,
popups, dialogs, and multi-display behavior still require manual acceptance.
