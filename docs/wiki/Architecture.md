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
│  AXObserver │ EventTap │ WindowRenderer │ Yabai Backend│
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
  - **Accessibility APIs (`AXUIElement`, `AXObserver`)**: Discovers newly opened windows, tracks window destruction, and manages window focus.
  - **Core Graphics Event Tap (`CGEventTap`)**: Intercepts trackpad swipe/pinch gestures, mouse drags, and keyboard shortcuts.
  - **Yabai Scripting Addition Adapter**: Dispatches low-level WindowServer transforms for offscreen translation and overview scaling.
  - **IPC Server**: Listens on the Unix domain socket for CLI commands.
- All state updates to AppKit and Accessibility execute on the main thread.

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
