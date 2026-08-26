# macOS Infinite Window Manager

`minfwm` provides an infinite 2D canvas by storing window positions in virtual
coordinates and projecting the visible part onto macOS displays. The first
phase targets macOS 14+ and keeps native Spaces out of scope.

## Authorship

This project is fully written by AI. Human review remains required before use,
especially for Accessibility, WindowServer, SIP, and other privileged macOS
behavior.

## Requirements

- macOS 14 or newer, C++20, AppleClang, and CMake 3.20+.
- Accessibility permission for `minfwmd`.
- Yabai Scripting Addition is optional. The default AX backend does not require
  SIP changes; SA adds privileged movement/layer support when a compatible
  handshake succeeds.

## Build and Run

```bash
cmake -S . -B build -DCMAKE_OSX_DEPLOYMENT_TARGET=14.0
cmake --build build --parallel
ctest --test-dir build --output-on-failure
./build/minfwmd
```

Control a running daemon from another terminal:

```bash
./build/minfwmc reload
./build/minfwmc camera move --x 100 --y 0
```

The local socket is `$TMPDIR/minfwm.sock`; it is created for the current user
with mode `0600`. Invalid CLI arguments return a nonzero exit code.

## Configuration

The optional file is `~/.config/minfwm/minfwm.toml`. Only the documented subset
is accepted and reload is atomic:

```toml
enable-window-shadows = false
multi-display-mode = "isolated"
overscan-buffer-px = 500
whitelist = ["Terminal", "Music"]
spawn-behavior = "center"
```

Invalid values leave the active snapshot unchanged. `reload` reports a daemon
error when the file cannot be parsed.

## Architecture

- `src/core/` is platform-independent geometry, camera, display, and visibility
  state.
- `src/daemon/` adapts AXUIElement, AXObserver, CGEventTap, NSWorkspace,
  CFRunLoop, and the optional Yabai backend.
- `src/common/Protocol.hpp` defines the versioned `MFWM` IPC frame and response.

See [`docs/adr/`](docs/adr/), [`docs/research/macos-feasibility.md`](docs/research/macos-feasibility.md),
and [`docs/acceptance-macos.md`](docs/acceptance-macos.md) for design decisions
and manual checks. Live Accessibility, WindowServer, and SA tests remain
manual-only.
