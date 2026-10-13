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

## Recovery baseline and automatic transforms (2026-10-13)

Commit `85e6f5a` reconstructs the automatic lifecycle v1 backend from before
system jitter was reported, following the user's requested rollback point.
It is a historical comparison point, not an installed payload. The current
backend again selects transforms automatically, but requires lifecycle v2
capability 0x180. This supersedes the earlier startup opt-in/default-off policy.
The current-native-frame and partial-cleanup regression tests are retained.
Stock SA remains a fallback and does not guarantee above-menu-bar placement.

## Movement failure and offscreen culling (2026-10-13)

New fake-backend regressions failed before the fix: immediate rejection was
resent on each render; a changing camera bypassed suppression; fractional
positions resent identical integer commands; failed AX parking repeatedly
shrunk/restored windows; transformed culling reset and resized the native frame.
The renderer now caches integer targets, suppresses unchanged rejected targets,
backs off changed rejected targets for 250 ms and failed parking for 500 ms.
Partial geometry restoration remains retryable. With lifecycle v2 transforms,
fully offscreen windows keep their native size and use translation-only culling.
The new and existing renderer tests pass. Desktop smoothness and minimum-size
behavior still require a live check with the corresponding payload installed.

## Presentation cadence and bounded AX waits (2026-10-13)

The daemon now uses NSScreen/CADisplayLink callbacks per display instead of a
fixed 60 Hz update timer. The adapter rebuilds display links on screen-parameter
changes and invalidates/releases them before restoring windows. The fallback
timer is retained when display-link creation fails. Focus queries are cached
for 250 ms and updated by focus notifications, rather than sent across process
boundaries on every display frame. AX calls use a checked 100 ms process-wide
messaging timeout, reduced to 50 ms during shutdown. A separate signal timer
keeps exit independent of display-link callbacks. Shutdown logs identify input
stop, window restoration and completion.

The display-link scheduling idea follows the independently implemented API
pattern reviewed in Nehir; no GPL source was copied. The daemon still follows
pointer input directly; spring interpolation has not been added. Build checks
cover the adapter. Display cadence, multi-monitor timing, AX timeouts and actual
desktop exit remain manual-only checks. Per-call timeouts bound unresponsive
AX messages; total restoration time still depends on the number of windows.

A manual, window-free display-clock probe on this desktop received 125 callbacks
across the available displays in 0.5 seconds, stopped the clock twice safely,
and returned from the daemon run loop (exit 0). Evidence:
`build/manual-frame-clock.log`. This verifies live callback/stop behavior only;
it does not establish window-animation smoothness. Frame callbacks use their
own autorelease pool so the long-running daemon does not accumulate temporary
Objective-C objects until shutdown. Full build and all 11 CTests passed before
this adapter-only cleanup.

## Lifecycle v2 live acceptance and selected-window readback (2026-10-13)

The user installed the compiled payload; the live handshake is SA 2.1.29 with
capabilities 0x180. An isolated ordinary NSWindow passed 120 pan frames above
the menu bar, 20 translation-only offscreen round trips retaining its size,
45 seconds of settled-position checks, reset after the fixture changed its own
native AppKit frame, and owner-crash watchdog recovery. This pass did not test
clicking/typing; the input hold is not evidence of interactive input correctness.
Evidence: `build/lifecycle2-manual-live.log`.

The full daemon now starts successfully with Accessibility access in this
environment. Its initial SIGTERM exit took 0.109 seconds. Inspection also found
five windows retaining old presentation offsets from before this pass. With
minfwmd stopped, only those known AX application windows were normalized against
their current native frames. Visual/native origins then agreed. Evidence:
`build/lifecycle2-legacy-repair.log`, `build/lifecycle2-native-clean.log`.
New SA installation alone did not clear these legacy offsets.

The first real-app pan check passed nine windows but failed Discord. A focused
probe showed its transform ACK succeeded and its full-session bounds remained
at the requested target; the selected-window CoreGraphics query returned an
empty array. The daemon had mistaken this readback failure for a failed move
and reset the transform before AX fallback. The adapter now falls back to the
full session list and matches the exact WID; it also rejects dictionaries for
other WIDs. The new fake-query tests failed before the change and pass now.
Evidence: `build/discord-transform-probe.log`, `build/discord-all-readback.log`.

After the readback fix, the production daemon/CLI passed all ten tested windows:
Telegram, Zen, Feishin, ChatGPT, OBS, Ghostty, System Settings, Obsidian, Zed and
Discord. Each followed camera y offsets 400 and 2200, including above-menu-bar
and fully offscreen positions, returned to its original position, and had its
native baseline restored on SIGTERM. Exit took 0.073 seconds, code 0, without
restoration-failure messages. Evidence: `build/real-pan-fixed-result.log` and
the `build/real-pan-fixed-*.log` snapshots.

Full build and all **12 CTests pass**. Commit `38ded66` contains the readback
fix; `127120f` adds the expanded manual fixture. Human assessment of panning
smoothness, ordinary native dragging, sheets/popups and multiple displays
remains separate from coordinate readback and timed-exit checks.

## Native input geometry and hybrid positioning (2026-10-13)

The first final-drop patch (`d7277d2`) passed state/fixture checks but the user
still observed a pickup jump and incorrect placement on the next pan. It was
reverted in `6182605`; the daemon was stopped before further investigation.

The isolated drag probe made the mismatch explicit: a window rendered at
(450,200) retained native/AppKit geometry at (120,448). Computer-use coordinate
validation refused a title-bar drag at the visible location. AX-only rebasing
then showed asynchronous native movement; resetting immediately exposed the
old native frame. A native SA move followed by transform reset aligned native
and visual bounds immediately without an AX-driven animation. The user dragged
the aligned fixture normally; logged native and visual positions followed the
drag together. Evidence: `build/drag-probe-live.log`,
`build/rebase-drag-live.log`, `build/rebase-server-live.log` and
`build/native-only-probe-live.log`. This proves the isolated aligned case, not
the complete daemon's interactive behavior.

The daemon now prefers native SA positioning where the frame's top is at/below
the display's usable top edge and at least 40 logical points remain visible on
each axis (or the whole axis for smaller windows). Elsewhere it keeps absolute
translation. The margin is a conservative placement policy, not a guarantee
that every application accepts the frame. Native failure still reaches the
transform/AX fallback. Native handoff moves the frame before clearing the
transform, and invalidates level bookkeeping after successful cleanup.
The final mouse-up adoption/cache fix is retained together with this geometry
change; it is no longer presented as sufficient on its own.

New geometry, renderer and transport regressions failed before implementation
and pass now, including negative origins and command order 0x14, 0x06, 0x15.
Full build and all 12 CTests pass. A repeat production-daemon test passed the
five windows still present under their original IDs: Zen, Feishin, ChatGPT,
Ghostty and Discord. All followed offsets 400/2200, returned and restored on
exit; all five returned with native/visual baselines aligned. Exit took 0.074 s.
Evidence: `build/hybrid-real-pan-result.log` and corresponding snapshots.
The other earlier application windows had closed or changed IDs and were not
counted as passes in this repetition.

The user subsequently tested native title-bar dragging after Cmd+Option
panning, dropping the window, and panning again. They confirmed that both the
pickup jump and incorrect placement on the next pan disappeared. This is a
human PASS for those two reported failures with the hybrid implementation
(`7ad3edc`), rather than an inference from coordinate-only tests. Opt-in input
tracing (`2badba8`) also recorded final drops using the camera captured before
the gesture; for example, physical (724,167) with camera (578,-99) became
virtual (1302,68). Evidence: `build/hybrid-interactive-live.log`.

The test process exited in 0.055 s but logged restoration failures while a
second minfwmd was running from the user's terminal. Its continuing window
moves invalidate that shutdown check in isolation. After stopping the remaining
process (0.131 s), all seven checked application windows had matching visual
and native origins and baseline transforms: Zen, Feishin, ChatGPT, Discord,
TeamSpeak and two Ghostty windows. No minfwmd process remained. Evidence:
`build/hybrid-interactive-settled.log`. Popups/sheets, multiple displays and
subjective animation smoothness still need separate acceptance checks.


## Scroll overview (2026-10-14)

Implementation: Cmd+Option vertical scroll requests cursor-anchored zoom between
20% and 100%; frame-time exponential easing advances on display presentation.
Pan deltas are divided by scale to track screen-space pointer movement.
Selection returns all displays to 100%, centers/raises the selected window and
consumes both ends of the click. Escape returns at the display center. Native
geometry synchronization and focus recentering are suppressed during overview.
Scale failure exits overview through the normal native/transform/AX path.

The SA keeps version 2.1.29 and adds capability 0x200 (total 0x380) and opcode
0x16 with an integer scale. The installer identifier changes to overview1;
exact generated v1/v2 build patches can be upgraded without overwriting unknown
changes. Loading requires the terminal's privileged loader, with minfwmd stopped.
The installed lifecycle v2 remains compatible and cannot receive scale packets.

Automated regressions failed before implementation: scaled coordinate and size
round trips with negative origins, cursor anchoring, expanded viewport, invalid
scale/anchor atomicity, bounded scroll, refresh-rate-independent easing, packet
bytes, capability gating, explicit ACK, truncated/invalid payloads, inverse
matrix and reset at the current native frame. Renderer tests cover no AX native
resize, duplicate suppression and native handoff at an unchanged position.
Full daemon/manual-target builds and all **12 CTests pass**. The new SA also
built twice successfully, exercising upgrade from the exact lifecycle v2 patch
and rebuilding an already patched checkout. The installed-payload fixture
returned **77 (skipped)** because the existing SA lacks overview capability;
it did not apply a scale. Evidence: `build/zoom-installed-sa-check.log`,
`build/zoom-final-build.log`, `build/zoom-sa-build.log`,
`build/zoom-sa-rebuild.log`. No daemon was left running.

Live checklist (pending new payload installation):

- Run `minfwm_manual_window_move --overview-fixture` with minfwmd stopped:
  120 scaled-frame origins/sizes, return to native geometry, owner-crash cleanup.
- Start exactly one daemon. Zoom around several cursor positions, pan at 20%,
  select a window, then drag its title bar and pan again; confirm no jump.
- Escape while zooming; release modifiers before scroll momentum ends; confirm
  no scroll/click/key event leaks into application content.
- Quit while zoomed; check native scale, position and ordinary dragging.
- Repeat with popups/sheets and displays with negative origins. Check scroll
  without overview support still reaches applications normally.

After the user loaded the new payload, the isolated ordinary NSWindow fixture
passed all 120 scaled-frame origin/size checks, returned to native geometry,
and recovered from an owner process exiting without destructors. The fixture
exited 0. Evidence: `build/zoom-live-fixture.log`. This establishes the isolated
WindowServer path; production event-tap interaction, application compatibility
and subjective smoothness remain separate checks.

### Desktop input follow-up

The first human desktop check **failed**: overview did not start, and canvas
movement appeared to update only every 10–20 frames. The isolated SA fixture
PASS above did not establish event-tap integration. The daemon was stopped.

Wheel tracing then recorded no scroll events at the session tap during the
user's repeated gesture. The tap inventory confirmed Mac Mouse Fix's scroll
filter at HID. A dedicated wheel-only HID tap is now placed ahead of mouse
utilities, with annotated-session fallback when HID creation is unavailable;
the original session tap still owns native dragging, keyboard and pan input.
Actual wheel delivery with this change remains pending human verification.

Visibility inspection showed Feishin, Discord and Ghostty were user-hidden.
Their zero presentation origins/identity matrices are not evidence of leftover
transforms. They must not be repeatedly moved, unhidden or scaled by the daemon.
The renderer now suspends owned presentation without AX geometry writes, and
application hide/unhide notifications resume the unchanged virtual model.
A focused regression failed before suspension implementation and passes now.

Sampling also found synchronous LaunchServices lookups for application names
and visibility inside each frame. These are now cached from application
observation and hide/unhide notifications. A repeat two-second sample contained
no `NSRunningApplication.isHidden` or `localizedName` stack in frame processing.
24 production IPC camera commands (12 forward, 12 back) passed, averaging
5.84 ms including CLI launch, maximum 20.36 ms. This is command latency, not a
measured presentation FPS or a subjective smoothness pass. Evidence:
`build/zoom-input-fixed-sample.txt`, `build/zoom-metadata-sample.txt` and
`build/zoom-metadata-live.log`. Full build and 12/12 CTests pass after these fixes.

### Unpresented auxiliary dialog regression

The user confirmed much smoother ordinary canvas movement after the input and
application-state fixes, but still saw position changes without sustained zoom.
Wheel traces now show `requested=1`; every negative scroll was followed by an
overview failure and return to unit scale. This supersedes the earlier missing
wheel-delivery failure.

With the daemon stopped, direct real-window checks passed scale 0.5 and reset
for Zen (1117x959 -> 559x480), ChatGPT (1378x804 -> 689x402) and Antigravity
(1400x900 -> 700x450). An unpresented ChatGPT AXDialog (WID 7727, 64x64) failed
the same operation. Yabai's read-only metadata reported that dialog invisible,
with a zero AX frame, while the three main windows were AXStandardWindow and
visible. Evidence: `build/zoom-real-window-probe.log`,
`build/zoom-metadata-live.log`.

The adapter now records auxiliary subroles when first capturing geometry and
uses a batch onscreen-ID snapshot to suspend unpresented auxiliaries without
moving/resizing/unhiding them. Windows culled by minfwm retain their canvas
participation. Unknown WID 0 cannot receive overview commands. Suspended
auxiliaries are not restored with AX geometry on shutdown. Snapshot parsing
regressions failed before implementation and pass now; full build and all
12 CTests pass. Commit `f8ce7dd`; sustained human zoom/selection validation is
pending on the restarted daemon.

The user subsequently confirmed that zoom and selection now work, and requested
a smoother return animation plus configurable scroll inversion. This is a human
PASS for sustained overview and click-to-return after the auxiliary fix.

### Return animation and scroll direction

Selection and Escape now use a 0.36-second quintic easing curve. Scale changes
logarithmically while the virtual viewport center interpolates to the selected
window; Escape holds the center fixed. Input remains owned by overview until
all windows have returned to native geometry. Wheel/pan input cannot interrupt
the return transition. Operation failure retains immediate unit-scale recovery.

`invert-zoom-scroll-direction` is a strict boolean in the existing TOML config,
default false. It reverses only overview wheel deltas and takes effect on
`minfwmc reload`. No live config existed, so the documented default example was
created at the standard location with inversion disabled; `minfwmc reload`
succeeded. Existing user files are preserved.

New focused tests failed before implementation: no immediate selection jump,
intermediate scale/input ownership, exact final camera/scale, 60/120 Hz paths,
Escape anchor and cancellation, plus true/false/default parsing and atomic
rejection of non-boolean/duplicate config values. Full build and all 12 CTests
pass. Subjective return smoothness and live inversion/reload remain manual
checks for this follow-up.

### Escape anchor and native handoff (2026-10-14)

The user confirmed the smooth return behavior, but reported a one-frame flash
at completion and requested `zoomed-esc-center`. Config now accepts the strings
`"screen"` (default), `"mouse"`, and `"focus"`. Screen keeps the virtual display
center; mouse fixes the point under the cursor throughout the transition on
that display; focus centers the last valid focused managed window, falling
back to screen center if it has closed/hidden. Selection clicks retain their
existing center-on-window behavior. The live config received only the missing
new key, preserving other settings. Focus is frozen while overview owns input.

A disposable-window probe reproduced the handoff gap: its presentation origin
was (319,19), but the separate stock native move exposed (599,-229) before
reset. Evidence: `build/zoom-handoff-position-probe.log`. Coordinate checks
after the complete move/reset pair had missed this intermediate state.

SA overview2 adds capability 0x400 (total 0x780), opcode 0x17 and a new installer
identifier. The owned native move, geometry association and unit transform now
run in one payload operation with WindowServer updates suspended until all
geometry changes finish. Every post-suspension failure reenables updates;
reenable failure is reported and retried. Layer ownership remains captured
until final reset/process death; native interaction itself clears the active
transform. Clients require all prior capabilities before using the new opcode;
older payloads retain the separate native-move/reset fallback.

Focused tests failed before implementation and now pass: strict Escape enum
validation, negative-origin cursor anchoring through the animation, native
handoff framing/capabilities, single-command handoff, preserved cleanup ownership,
peer/length rejection before suspension and release after move/transform/enable
failures. Full build and 12/12 CTests pass. The pinned SA builds successfully;
live atomic-handoff sampling and subjective flash validation remain pending
installation of the new payload. Commits: `a9ff13f`, `7a4b70c`, `58ff911`.

The installed overview2 payload passed 120 scaled fixture frames, native return,
ownership cleanup and crash recovery, but rejected the atomic handoff before
client readback. A separate owned-window API probe returned success for update
suspension, native move, bounds, transform and resume; geometry association
returned an arbitrary nonzero value. LLDB disassembly on this macOS 27 host
showed `SLSReassociateWindowsSpacesByGeometry` consists only of `ret`, with no
defined status. Evidence: `build/zoom-atomic-diagnostic-live.log`,
`build/atomic-api-probe-live.log`, `build/atomic-api-disassembly.log`.

The payload now retains that legacy side effect without treating its undefined
return register as CGError. All actual geometry/update results and client
position readback remain checked. A regression fake returning the observed
arbitrary value failed before the change and passes afterward; full build and
12/12 CTests pass. Installer identity overview3 ensures the corrected payload
replaces overview2. Live handoff and subjective flash checks require this build
to be loaded; the daemon remains stopped until then.

After the user loaded overview3, the disposable-window fixture passed all live
checks: 120 scaled frames; atomic handoff with successful client readback at
(400,200), 16 sampled positions and zero intermediate positions; native return;
ownership cleanup; and recovery after owner process death. Evidence:
`build/zoom-overview3-live-fixture.log`. This validates the installed handoff
path; it does not establish the absence of a visually perceptible flash across
third-party applications. The updated daemon was started for that human check.
Live reload accepted `mouse`, `focus`, and `screen` in turn; the exact original
config was then restored and reloaded (currently `screen`). This confirms live
configuration acceptance; subjective anchoring behavior is still a manual check.

### Desktop regression and compatible handoff rollback (2026-10-14)

The user rejected overview3 desktop behavior: windows became jerky and overview
stopped working. The daemon was stopped normally. Its log shows repeated overview
failures on ChatGPT WID 7726 from the first wheel event, with shutdown restore
failures for ChatGPT and Ghostty. After shutdown, Ghostty's visible/native frame
matched, but the visible ChatGPT window had an identity matrix and origin (0,0)
against native (316,136). Only that known visible ChatGPT window was normalized;
hidden applications were left untouched. Evidence:
`build/zoom-esc-overview3-live.log`, `build/overview3-regression-state.log`,
`build/overview3-repair.log`.

Following normalization, isolated real-ChatGPT probes passed repeated
overview/native/overview transitions and three production WindowManager
zoom/return/pan cycles. The exact trigger for the bad baseline was not reproduced.
The external fixture hide/unhide requests returned false, so they provide no
visibility-lifecycle validation. Single-window atomic success does not explain
or resolve the reported desktop regression.

The daemon now defaults to the previously accepted stock native move plus full
transform reset, even with an installed atomic capability. Atomic handoff is
available only through explicit constructor opt-in in isolated tools/tests;
there is no daemon or config opt-in. Zoom, smoothing, inversion and Escape
anchor settings remain intact. A default-policy regression test failed before
this change and passes now; all 12 CTests pass. The compatible live fixture
passed 120 scaled frames, native handoff readback, original-frame restoration,
ownership cleanup and crash recovery. Evidence:
`build/overview-compatible-fixture-live.log`. This is a containment rollback;
the one-frame flash and the original desktop trigger remain unresolved. The
daemon remains stopped pending confirmation of normal native interaction.
The compatible backend also passed three isolated production WindowManager
cycles on ChatGPT (zoom to 20%, smooth Escape return, pan above the menu bar and
back, shutdown). After the probe exited, both visible application windows
(ChatGPT and Ghostty) had matching native/visible origins and native baseline
matrices. Evidence: `build/window-manager-compatible-chatgpt.log`,
`build/overview-compatible-final-state.log`. No further real-window probes or
daemon runs are active.
