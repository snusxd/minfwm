# Features

`minfwm` transforms your macOS workspace into an infinite 2D canvas, allowing you to freely position, organize, and navigate windows without the constraints of traditional monitors or Spaces.

## Infinite Canvas & Navigation

- **Infinite 2D Workspace**: Place windows anywhere on an endless virtual desktop.
- **Trackpad & Mouse Panning**:
  - Pan smoothly across the canvas using a three-finger trackpad swipe (with natural momentum) or `Super` + left-click drag.
  - Multipliers and axis inversions available for complete sensitivity control.
- **Zoom & Overview**:
  - Zoom out to an aerial view of your canvas with a four-finger trackpad pinch or `Super` + scroll wheel.
  - Click any window in overview mode to zoom in and center it.
  - Press `Escape` to quickly exit overview.
- **Camera Bookmarks**: Save up to 9 camera positions (`Super + 1..9`) and instantly jump between them (`Super + Shift + 1..9`).
- **Precision CLI Navigation**: Move the camera to exact coordinates directly from the terminal (`minfwm camera move --x 100 --y 0`).

## Window Management & Ergonomics

- **Drag Everywhere**: Hold `Super + Ctrl` and drag anywhere inside a window (or swipe with three fingers) to move it without reaching for the title bar.
- **Smart Window Snapping**: Smoothly snaps near-fullscreen windows into place along display edges after panning, with customizable threshold and alignment.
- **Window Pinning**: Pin frequently referenced windows (`Super + P`) so they follow the camera wherever you pan, with optional always-on-top floating.
- **Quick Centering**:
  - Center the camera on the focused window (`Super + F`).
  - Pull the focused window to the center of your screen (`Super + S`).
  - Automatically center the camera when switching apps with `Cmd + Tab`.
- **Display Isolation & Multi-Monitor**:
  - Independent virtual canvases for each physical display (including secondary monitors with negative origins).
  - Configure `ignored-displays` to leave specific monitors unmanaged for standard macOS usage.
- **Safe Window Lifecycle**:
  - Discovers new windows automatically as applications open.
  - Automatically restores all captured windows to their original positions when the daemon exits.

## Performance & Control

- **Smooth Animations**: Hardware-paced easing for panning, zooming, and snapping with configurable animation speeds.
- **Background Daemon**: Managed easily via `minfwm start`, `stop`, `restart`, `status`, and login auto-start (`minfwm enable` / `disable`).
- **Atomic Configuration**: Edit `~/.config/minfwm/minfwm.toml` and reload on the fly with `minfwm reload`. Invalid changes are automatically rejected without disrupting your workflow.
