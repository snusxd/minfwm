# Architecture

This document outlines the core architecture, design principles, and component boundaries of `minfwm`.

---

## Architectural Boundaries

`minfwm` is structured to separate platform-independent window geometry from macOS-specific system integration:

```
┌────────────────────────────────────────────────────────┐
│                        minfwm CLI                      │
│                  (Command-line control)                │
└───────────────────────────┬────────────────────────────┘
                            │ Unix IPC Socket
┌───────────────────────────▼────────────────────────────┐
│                      minfwm Daemon                     │
│ AXObserver │ EventTap │ WindowManager │ Preview Capture│
│              │ Renderer │ Yabai SA Backend            │
└───────────────────────────┬────────────────────────────┘
                            │ Pure C++20 State & Math
┌───────────────────────────▼────────────────────────────┐
│                        Core Engine                     │
│  Geometry │ Camera Math │ Visibility Policy │ Snapping │
└────────────────────────────────────────────────────────┘
```

### 1. Core (`src/core/`)
- Written in modern, pure C++20.
- Contains geometry math, camera transformations, viewport projections, visibility culling, and edge-snapping algorithms.
- **Zero macOS API dependencies**: Completely decoupled from AppKit, Core Graphics, and Accessibility APIs, allowing comprehensive headless testing on any system.

### 2. macOS Daemon (`src/daemon/`)
- The background daemon process invoked by `minfwm daemon`.
- Hooks into macOS subsystems:
  - **Accessibility APIs (`AXUIElement`, `AXObserver`)**: Discovers windows, tracks lifecycle and focus, reads and sets supported window attributes, and invokes the native Fill menu action when available.
  - **Core Graphics Event Tap (`CGEventTap`)**: Handles trackpad swipe/pinch, mouse pan and window dragging, and keyboard shortcuts.
  - **Window manager and renderer**: Keep each managed window's canvas rectangle, project it through its owning display camera, and apply or clear WindowServer presentation transforms. A user drag can transfer ownership between managed displays or release a window onto an ignored display.
  - **Yabai Scripting Addition adapter**: Performs offscreen translation, overview scaling, and temporary pinned levels. Startup requires a compatible transform and pinned-level handshake; it aborts if either capability is missing.
  - **Overview previews**: Optionally capture distant windows with ScreenCaptureKit and present snapshots in display overlay layers. Focused, pinned, whitelisted, selected, auxiliary, and actively dragged windows stay live. If Screen Recording access or capture is unavailable, windows remain live. Preview selection can focus a live original while preserving the current overview scale when `rewind-on-focus = false`.
  - **IPC server**: Listens on the Unix domain socket for CLI commands.
- AppKit, Accessibility, and window presentation updates are coordinated on the main thread; screenshot capture completes asynchronously.

### 3. CLI & IPC (`src/cli/` & `src/common/`)
- `minfwm` is a unified executable providing both the daemon and CLI control tools.
- Commands communicate with the running daemon over a private Unix domain socket at `$TMPDIR/minfwm.sock` (file mode `0600`, accessible only by the current user).
- Uses a compact, versioned binary protocol (`Protocol.hpp`) ensuring low-latency communication.

---

## Coordinate Model & Virtual Canvas

Instead of moving windows across rigid desktop spaces:
1. **Virtual Space**: Every window lives at specific 2D coordinates `(X, Y)` on an endless canvas.
2. **Camera Projection**: Each physical display acts as a viewport (camera) into this virtual canvas.
3. **Multi-Display Isolation**: Connected displays maintain their own independent cameras and canvases. Secondary displays with negative coordinate origins are seamlessly mapped to the global coordinate space.
4. **Visibility & Culling**: Windows that move far outside the visible camera view are culled from active rendering to conserve system resources, while their positions are preserved in memory.
5. **Clean Exit**: When the daemon shuts down, all custom WindowServer transforms are cleared, and windows are restored safely to their original native positions.

## Window Interaction

- **Drag Everywhere** (`Super + Ctrl` by default) starts a window drag from its content area. A three-finger swipe can also move a window. Dragging a clipped title bar uses a model-space fallback so the window can be brought fully back onto the display.
- **Temporary Fullscreen** uses the application's native macOS Fill action (available on macOS 15+ when the app exposes that menu command). The daemon preserves the previous frame and restores it when the camera pans or zooms; it does not replace the app's native Fill animation.
- **Overview previews** are an optional rendering optimization, not a second window model. Snapshots occupy the same projected display bounds as the original window, while the original is parked until it needs to become interactive again.
