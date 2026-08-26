# minfwm: macOS Infinite Canvas

## Supported baseline

The daemon targets macOS 14+ with C++20 and CMake. Accessibility permission is
required. Window operations use public `AXUIElement` and `AXObserver` APIs;
`CGEventTap`, `NSWorkspace`, and `CFRunLoop` provide input and lifecycle events.
Yabai Scripting Addition is optional and is enabled only after a compatible
handshake. SIP changes are not required for the baseline.

The canvas is an emulated virtual workspace: each display has a camera and
windows retain virtual coordinates. `src/core/` converts virtual geometry to a
canonical physical coordinate system, including negative secondary-display
origins. Native macOS Spaces are intentionally not implemented in phase one.

## Runtime flow

1. `minfwmd` checks Accessibility permission and snapshots connected displays.
2. `AXObserver` tracks application and window events on the main run loop.
3. `InputInterceptor` consumes Cmd+Option panning and restores a timed-out
   event tap.
4. Visibility culling keeps focused and whitelisted windows available; other
   windows use one AX hide policy and are restored on shutdown.
5. All AppKit/AX state changes execute on the main thread. IPC workers validate
   frames, enqueue commands, wait for a response, and never mutate window state.

## IPC

Use:

```bash
./build/minfwmc reload
./build/minfwmc camera move --x 100 --y 0
```

The `MFWM` version-1 frame has a little-endian command and payload length capped
at 64 bytes. `RELOAD` has no payload; `CAMERA_MOVE` has two finite `float32`
values. Reserved commands are unsupported and return an error response. The
socket lives at `$TMPDIR/minfwm.sock`, is user-owned, and is mode `0600`.

## Configuration and validation

`~/.config/minfwm/minfwm.toml` supports only the keys documented in `README.md`.
Reload parses a candidate snapshot first and keeps the last valid snapshot on
failure. Run the CMake build and CTest suite before integration. Use the manual
matrix in `docs/acceptance-macos.md` for Accessibility, panning, focus,
secondary displays, orderly shutdown, and optional SA behavior.
