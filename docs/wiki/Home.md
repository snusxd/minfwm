# minfwm Wiki

Welcome to the `minfwm` documentation!

`minfwm` is an infinite 2D canvas window manager for macOS 14+. It replaces the concept of traditional virtual desktops (Spaces) with a single continuous 2D surface. You can pan anywhere, zoom out for an overview, organize windows freely, and navigate quickly with trackpad gestures and keyboard shortcuts.

## Documentation Pages

- **[Getting Started](https://github.com/snusxd/minfwm/wiki/Getting-Started)**: Requirements, installation, starting the daemon, and default shortcuts.
- **[Configuration](https://github.com/snusxd/minfwm/wiki/Configuration)**: Complete guide to configuring shortcuts, trackpad sensitivity, snapping, and animations in `minfwm.toml`.
- **[Yabai Integration](https://github.com/snusxd/minfwm/wiki/Yabai-Integration)**: Why the Yabai Scripting Addition is required, how to build and load it, and SIP prerequisites.
- **[Architecture](https://github.com/snusxd/minfwm/wiki/Architecture)**: High-level overview of core geometry, macOS platform adapters, and IPC protocol.
- **[Development](https://github.com/snusxd/minfwm/wiki/Development)**: Building from source, testing with CTest, and developer tools (`dev-update`).
- **[Releases](https://github.com/snusxd/minfwm/wiki/Releases)**: Versioning scheme, upgrading releases, and checking installed version.

## Requirements at a Glance

1. **macOS 14+ (Sonoma or newer)**.
2. **Accessibility Permission**: Required for window discovery, focus tracking, and coordinate mapping.
3. **Disabled System Integrity Protection (SIP)**: Necessary to load the Yabai Scripting Addition.
4. **Compatible Yabai Scripting Addition**: Allows windows to be positioned smoothly offscreen and above the menu bar. See the [Yabai Integration guide](https://github.com/snusxd/minfwm/wiki/Yabai-Integration) for simple setup instructions.
