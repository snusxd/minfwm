# macOS Acceptance Matrix

## Daemon exit regression (2026-10-13)

An isolated Foundation timer reproduced the exit hang without AX permission:
`CFRunLoopStop` returned from an inner run but `NSRunLoop.run` continued waiting.
The dedicated daemon run-loop CTest timed out before the fix. The daemon now
uses one `CFRunLoopRun` invocation, allowing its existing shutdown timer to
return to main after stopping producers and restoring windows. The regression
test passes without creating windows or invoking live Accessibility APIs.
Full desktop exit/restoration remains a separate manual check.

Automated checks run on every integration pass:

```text
cmake -S . -B build -DCMAKE_OSX_DEPLOYMENT_TARGET=14.0
cmake --build build --parallel
ctest --test-dir build --output-on-failure
```

Manual checks on macOS 14+ require Accessibility permission. Verify daemon
startup without Yabai SA, Cmd+Option panning, focused-window behavior, a
secondary display with a negative origin, launch/terminate, `minfwmc reload`,
malformed CLI/config input, and orderly shutdown restoration. Repeat movement
and layering with a compatible Yabai SA installed; confirm handshake failure,
timeout, invalid ACK, and missing socket all fall back to AX without blocking
startup.

Sanitizers apply to the pure C++ core only. Live Accessibility, WindowServer,
CGEventTap, and SA behavior cannot be proven by portable tests and must be
reported separately from automated results.

## Runtime regression checks (2026-10-13)

| Requirement | Automated evidence | Live macOS check |
| --- | --- | --- |
| Isolated display panning, including negative origins | `minfwm_pan_gesture_tests`: display selection, shared edges, crossing displays, modifier release, tap reset | Pending: drag on a secondary display and release modifiers before mouse-up; check bookmarks there |
| Window ownership and application termination | `minfwm_window_pool_tests`: PID removal clears AX/WID indexes and is idempotent | Pending: launch, create/close multiple windows, quit and relaunch the application; verify per-window notifications |
| AX fallback and partial hide/show recovery | `minfwm_window_renderer_tests`: fake backends exercise failed SA movement/layering, failed parking rollback and restoration retries | Pending: repeat without SA and with a compatible SA; observe actual AX minimum-size/position constraints |
| Orderly shutdown restoration | `minfwm_window_renderer_tests`: original physical geometry is independent of camera position; size and layer restoration continue after a failed move | Pending: pan until windows are culled, send SIGTERM, check original geometry, visibility and normal SA layer |
| Exclusive socket ownership and restart | `minfwm_local_socket_tests`: crashed owner, legacy active socket, stale socket, replaced inode and unsafe paths; `minfwm_ipc_server_tests`: duplicate startup, wakeup descriptor cleanup, partial frames, stop/restart and destructor | Pending: start a second daemon and verify rejection before any window changes |
| Finite camera state | `minfwm_geometry_tests`: overflowing/non-finite updates preserve both coordinates | Pending: check CLI error propagation after accumulated camera overflow |

Full build and all nine CTest targets passed. Geometry and gesture tests also
passed with AddressSanitizer and UndefinedBehaviorSanitizer. Backend tests use
recording fakes and local test sockets; live Accessibility, CGEventTap,
WindowServer and Yabai SA checks were not performed in this implementation pass.

## Menu-bar movement regression (2026-10-13)

Automated: full build and all nine CTest targets pass. The SA fake server covers
zero handshake flags, numeric version validation, truncated handshakes, negative
coordinates, EOF, invalid ACK and timeout. Backend/renderer tests cover readback
mismatch reaching AX, delayed application correction, a single AX recovery
attempt, suppression of repeated rejected targets, return to a new target, and
SA movement after restoring window size. Layer restoration uses
`kCGNormalWindowLevelKey` (4), not the base-level key (0).

Live environment: Apple Silicon, macOS 27.0 build 26A428, Yabai 7.1.25,
SA 2.1.29 with handshake flags 0x0. The explicit manual target creates its own
window and removes it on completion; existing application windows are untouched.

| Check | Result | Evidence |
| --- | --- | --- |
| Zero-flag SA handshake | Pass | SA backend reports ready |
| Normal titled NSWindow remains at y=-120 | **Fail** | Immediate WindowServer readback is `(120,-120)`; after application events it is `(120,31)` |
| Detect delayed correction | Pass | Renderer emits `position rejected after readback`; unchanged target is not continuously resent |
| Return normal fixture | Pass | Requested and settled position are both `(120,448)` |
| Higher window level removes constraint | Fail (diagnostic experiment) | Raising the fixture to dragging level still resulted in y=31 |
| Unconstrained fixture remains at y=-120 | Pass (diagnostic control only) | Overriding `constrainFrameRect:toScreen:` in the fixture preserves `(120,-120)` after events |
| Return unconstrained fixture | Pass | Requested and settled position are both `(120,448)` |
| Live AX fallback and resize/reappearance | **Skipped** | The separate manual binary has no Accessibility permission; these paths are covered only by fakes in this pass |

Reproduce explicitly outside CTest:

```bash
cmake --build build --target minfwm_manual_window_move
./build/minfwm_manual_window_move
./build/minfwm_manual_window_move --unconstrained-fixture
```

The normal fixture exits 1 for the unresolved constraint; the control exits 77
when live AX checks are unavailable. Logs from this pass are in
`build/manual-window-move.log` and `build/manual-window-move-control.log`.
This fix enables SA and detects incorrect positioning; it does **not** establish
unrestricted placement of third-party AppKit windows on macOS 27. No SIP,
system configuration, or third-party application code was changed.

### WindowServer transform prototype

Follow-up live check on the same environment uses an ordinary NSWindow with
no `constrainFrameRect` override. Invoke explicitly:

```bash
cmake --build build --target minfwm_manual_window_move
./build/minfwm_manual_window_move --transform-fixture
```

Yabai's existing `WINDOW_SCALE (0x0d)` PIP handler calls
`SLSSetWindowTransform`. Supplying four times the window width produces a scale
of 1 and a pure translation. This is diagnostic use of a toggle; an absolute
transform operation is needed before adopting it for camera updates.
Source: [Yabai 7.1.25 payload](https://github.com/asmvik/yabai/blob/v7.1.25/src/osax/payload.m#L595).

Result: **pass**, exit 0. AppKit's frame origin remained `(120,200)` in its
bottom-left coordinate system across event processing. WindowServer reported
`(120,-120)` after 1.2 seconds, then `(120,448)` after resetting the transform.
The normal move test previously corrected to y=31; this transform test did not.
Log: `build/manual-window-transform.log`.

This proves stable visual translation for the fixture, not completed daemon
integration. Mouse hit testing, typing/focus, popups and sheets, continuous
panning, multiple displays and shutdown/crash recovery still require checks.

## Integrated absolute transforms (2026-10-13)

Historical lifecycle v1 results below are **superseded for release readiness**
by the persistent-transform regression and recovery section. The fixture pass
did not cover native dragging of third-party application windows.

The daemon now selects the absolute setter when the pinned SA 2.1.29 handshake
advertises extension bit 0x80. Stock SA retains ordinary movement. Exact-length
commands 0x14/0x15 require explicit ACKs; EOF is not success. The payload
validates peer PID, stores original transforms/levels, and restores them when
the owner's PID/start-time identity disappears. Native geometry synchronization
uses the visual WindowServer position for transformed windows.

Build and all **10 CTest targets pass**. The additional payload target runs the
actual parser/state code against fake WindowServer functions: malformed frames,
peer identity, coordinate range, absolute repeated updates, original snapshot
restoration, idempotence, unsupported preexisting scale, failure/retry and
watchdog cleanup. Transport tests verify capability/version gating, explicit
ACK requirements, repeated targets, reset and AX fallback. Renderer tests cover
reset before hide/resize/shutdown and reapplying levels after reappearance.

Live environment remains Apple Silicon/macOS 27.0, Yabai 7.1.25. The user loaded
the custom SA. Verified handshake: `2.1.29`, flags `0x80`. An initial installer
with a different version was replaced by the user's existing stock autoloader;
the final installer preserves the pinned upstream bundle version and supplies
a distinct payload identifier, so that autoload configuration is unchanged.

| Live check | Result |
| --- | --- |
| 120 sequential pan frames through production backend/renderer, checking each visual position | Pass |
| Window remains above menu bar during input test; AppKit origin remains unchanged | Pass |
| Click test button in transformed window | Pass: fixture logs `INPUT click PASS` |
| Focus text field and type `minfwm-input-test` | Pass: AX state and fixture text-change events show the complete string |
| Reset to original WindowServer position | Pass |
| Separate process transforms window and exits without destructors; Dock watchdog restores it | Pass |
| AX hide/resize and orderly full-daemon shutdown | Pending live; covered by fake backends |
| Popup menus, sheets/dialogs, multi-display and drag/focus interactions with third-party applications | Pending |

The explicit live command is
`./build/minfwm_manual_window_move --absolute-fixture`; it creates a disposable
window, performs the pan check, provides 45 seconds for input, then checks reset
and process-death recovery. UI automation used a disposable app bundle around
the same fixture executable; no other application's windows were moved.
Evidence: `build/manual-absolute-input.log` (exit 0) and
`build/transform-daemon-build.log`. SIP and the user's Yabai configuration were
not changed.

## Persistent transform regression and recovery (2026-10-13)

The user reported severe native dragging/animation jitter even with minfwmd
stopped. Replacing the custom payload with stock Yabai SA removed continuous
jitter, but windows still jumped when released. Stopping the Yabai service did
not remove the release jump. This separates the residual geometry problem from
the running window-manager processes.

Read-only WindowServer inspection found visual/native frame disagreement in the
affected ChatGPT and OBS main windows. Their unit-scale translations referred
to an earlier frame origin. Replacing/unloading the SA had not cleared these
per-window transforms. Only those two known affected windows were normalized
against their current native bounds using stock SA's PIP reset path. After
normalization, visual and native origins matched. The user confirmed normal
dragging/release with both managers stopped, then confirmed it again after
the ordinary Yabai service was restarted. minfwmd remains stopped; stock
SA 2.1.29 remains loaded. No new experimental payload was loaded in this pass.

The old cleanup replayed a captured translation even if the native frame had
changed. Lifecycle v2 instead clears translation relative to current native
bounds. A separate cleanup bug could reapply transforms every 250 ms while
retrying a failed layer reset; v2 records successful transform cleanup and
retries only the unfinished layer operation. That retry bug is demonstrated
by a fake failure test; it was not independently traced during the live jitter.

| Check | Result / evidence |
| --- | --- |
| Restore after native frame changes | Payload regression test fails before the fix, passes with current native bounds |
| Failed level restoration does not repeatedly reset geometry | Payload regression test fails before the fix, passes with separate cleanup state |
| Preexisting foreign/stale translations | Payload rejects adoption outside the native baseline |
| Unsafe lifecycle v1 handshake | Transport tests reject 0x80 without lifecycle v2 bit 0x100 |
| Explicit opt-in | Config/backend tests confirm transforms default off even with a capable SA |
| Full daemon build and CTest | Pass: 10/10 (`build/recovery-build.log`) |
| Pinned lifecycle v2 SA build | Pass (`build/recovery-sa-build.log`); built only, not installed |
| Existing third-party windows after repair | Pass: user confirms normal dragging before and after restarting stock Yabai |
| Lifecycle v2 native dragging, resizing and app-driven frame changes during translation | Pending live |
| Lifecycle v2 orderly exit, owner crash and Dock/SA replacement after native frame changes | Pending live |
| Lifecycle v2 popups/sheets and negative-origin multiple displays | Pending live |

Local diagnostic evidence: `build/system-transform-visible.log`,
`build/repair-transforms.log`, `build/system-transform-after.log`.
These are local observations, not portable automated tests. Removing an SA is
not itself a proof that WindowServer has reset all affected windows.

The startup-only option `experimental-window-transforms` defaults to false.
Enabling it additionally requires lifecycle v2 capability 0x180 and exact
SA version 2.1.29. Changing this option requires daemon restart. Ordinary
movement and AX fallback remain available with stock SA.
