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

## System Limitations

- Accessibility permission is required for `minfwmd`; restart the daemon after
  granting or changing the permission. Add `yabai` separately if SA is used.
- Public AX can move, resize, hide, and observe regular windows. Applications
  can constrain their frames below the menu bar, including after an initially
  successful move. A higher WindowServer layer does not remove that constraint.
  Stock SA direct movement has the same application correction risk. The
  experimental minfwm SA extension translates the rendered window while
  retaining its AppKit frame. It demonstrated placement above the menu bar,
  but its first revision caused persistent offsets and native dragging jumps.
  Lifecycle v2 passed coordinate/exit checks with ten applications; ordinary
  native dragging and popup behavior still need manual checks. See the
  [live acceptance record](docs/acceptance-macos.md#lifecycle-v2-live-acceptance-and-selected-window-readback-2026-10-13).
- Yabai SA is private, version-sensitive, and requires a root loader plus the
  SIP configuration documented by Yabai. Do not weaken SIP for the default AX
  backend. Native macOS Spaces are not implemented; the canvas uses virtual
  coordinates and window projection instead.

### Known Yabai Compatibility Case

On Apple Silicon with macOS 27.0, Yabai `7.1.25` and SA `2.1.29` return zero
handshake flags. `SET_WINDOW (0x20)` describes the private focus function, not
movement or layering; its absence no longer disables those operations.
The complete handshake must still identify a numeric `2.x.y` protocol version.
See [Yabai's move and handshake handlers](https://github.com/asmvik/yabai/blob/v7.1.25/src/osax/payload.m).

Movement success requires actual position readback. SA uses WindowServer
bounds; the AX-only path uses AX position. An unapplied command reaches AX
fallback. The renderer checks again after 250 ms to detect application frame
corrections, attempts AX once, and rejects a persistently constrained target
until the camera target changes. Rejected positions do not overwrite the
virtual canvas or trigger a continuous move/correct loop.

The live check on this setup moved a normal `NSWindow` to `y=-120` initially,
but it returned to `y=31`. A diagnostic window overriding `constrainFrameRect`
stayed at `y=-120`; both windows returned to their original position. This
confirmed the AppKit correction in the original movement path. The experimental
transform backend avoids changing that frame; `minfwm` does not inject code
into managed applications. The fixture did not establish safe native dragging
after other applications changed their frames.

### Experimental window translation

The backend selects transforms automatically with a lifecycle v2 SA. The first
payload revision (`0x80`) is no longer accepted. Lifecycle v2 (`0x180`) has
automated regression coverage and passed live above-menu-bar/offscreen return,
native-frame cleanup and process-exit checks on macOS 27. Further interactive
checks remain listed in the acceptance matrix. To build and load the extension:

```bash
python3 tools/build_yabai_sa.py
sudo ./build/yabai-minfwm/bin/yabai --load-sa
```

The first command builds a pinned Yabai 7.1.25 extension locally. Loading it
replaces Yabai's installed SA and can restart Dock; it does not change SIP.
The daemon prints `absolute transforms enabled` with a lifecycle v2 capability
handshake. Stock SA remains supported with ordinary movement and AX fallback;
stock SA cannot guarantee above-menu-bar placement. No startup opt-in setting
is required.
See [extension setup and protocol](integrations/yabai/README.md).

Transforms are reset before AX visibility/size operations and orderly shutdown.
The revised SA clears translation using the current native frame and restores
the captured level if the owning daemon exits unexpectedly. Native dragging,
popup/dialog placement and multi-display behavior still need the manual checks
listed in the acceptance matrix. Unloading an SA alone does not necessarily
clear transforms already stored in WindowServer.

The daemon writes logs to stdout/stderr. Capture them with
`./build/minfwmd 2>&1 | tee /tmp/minfwmd.log`; Yabai service logs are commonly
`/tmp/yabai_$(id -un).out.log` and `/tmp/yabai_$(id -un).err.log`.

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
with mode `0600`. A user-owned `minfwm.sock.lock` in the same directory prevents
a second daemon from replacing the active socket. The lock file remains across
restarts; its lock is released automatically when the process exits. Invalid
CLI arguments return a nonzero exit code.

Cmd+Option dragging pans the display under the pointer when the gesture starts.
Window updates follow each display's presentation cadence. Pointer movement is
direct; spring interpolation is not implemented. Rejected moves and failed
parking operations are suppressed/backed off instead of retried every frame.
Releasing either modifier stops movement and consumes the rest of that captured
mouse gesture. Camera bookmarks also use the display under the pointer.
Orderly shutdown restores each window's captured physical position and size,
unhides windows hidden by the daemon, and resets successfully applied SA layers.

An explicit live check creates and removes its own temporary window:

```bash
cmake --build build --target minfwm_manual_window_move
./build/minfwm_manual_window_move
./build/minfwm_manual_window_move --unconstrained-fixture
./build/minfwm_manual_window_move --transform-fixture
./build/minfwm_manual_window_move --absolute-fixture
```

This target is excluded from the default build and CTest. Give the manual tool
Accessibility permission separately to check AX fallback and size restoration.
Exit `1` means a failed check; exit `77` means AX checks were skipped because
permission was unavailable. The unconstrained fixture is a diagnostic control,
not evidence that arbitrary third-party windows can stay above the menu bar.
The transform fixture checks a different approach on a normal NSWindow:
WindowServer translation while AppKit retains the original frame. This live
prototype stayed at `y=-120` and returned successfully on macOS 27. It uses
Yabai's PIP toggle at scale 1 as an earlier diagnostic. The absolute fixture
uses the integrated backend/renderer, checks 120 pan frames, holds the window
for input testing, resets it, and checks recovery after its owner exits without
cleanup. This mode requires the lifecycle v2
extension and exits 77 when it is unavailable. It does not replace native
dragging tests with third-party applications.

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
