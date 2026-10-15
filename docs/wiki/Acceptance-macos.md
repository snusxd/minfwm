# macOS acceptance

Accessibility, WindowServer, CGEventTap, window focus, and live Yabai SA behavior
are manual-only. Build/CTest success does not prove those interactions.

## Checks

- Start with the required Yabai SA; grant and revoke Accessibility permission;
  verify clear errors and orderly startup/shutdown.
- Pan with Super drag; verify focus, pin/unpin, native dragging, and camera
  bookmarks.
- With snapping enabled, pan a near-fullscreen window with Super drag and with
  three fingers. Verify the camera tracks the gesture freely, waits through
  trackpad momentum, then eases to the window edge. Start another pan during
  the snap animation and verify movement continues from the visible position.
  Repeat near a window smaller than 90% of either viewport dimension and verify
  that it does not trigger snapping.
  Repeat with snapping disabled and with animations disabled. Set each
  `snap.vertical-tuning` and `snap.horizontal-tuning` value in turn; verify the
  window lands on the selected edge or center, and `auto` keeps the nearest edge.
- Check a secondary display with a negative origin and independent cameras.
- With two displays in isolated mode, pan a focused window above the menu bar
  and across the edge of its owning display. Verify it does not flicker, clamp,
  or appear in the other display's camera; only a title-bar drag or drag
  everywhere should change ownership. After releasing drag everywhere at an
  unchanged position, verify hover follows the visible window.
- Connect a display while the daemon is running; verify it gets an independent
  camera, new windows are assigned to it, and native window drags transfer
  ownership between display canvases. Pan a camera until windows pass beyond its
  visible edge and verify those windows stay on their original canvas.
- With one display ignored, drag a window by its title bar and with drag
  everywhere from a managed display onto the ignored display. Verify the window
  remains visible and follows ordinary macOS positioning there. Drag it back
  and verify the managed camera picks it up without a jump. Pan the managed
  camera across the ignored display without dragging a window; its ownership
  must stay with the managed canvas. Repeat after changing `ignored-displays`
  and running `minfwm reload`.
- Verify window visibility, native geometry, and restoration after normal exit.
- Check translation, overview zoom, selection, Escape, application frame
  correction, and process-exit recovery.
- Check popups, sheets/dialogs, multiple displays, dragging during and after
  translation, and behavior when Yabai or the daemon restarts.

## Current evidence

On 2026-10-15, macOS 27.0 on Mac16,6 with yabai v7.1.25 reported absolute
transforms and pinned-level support at daemon startup. A three-finger trackpad
check of the animated snap was reported by the user as generally working; the
daemon trace emitted `CAMERA_SNAP ... animated`. With
`vertical-tuning = "bottom"` and `horizontal-tuning = "center"`, the user
confirmed that a three-finger snap placed the window at the bottom center.
The new `[snap]` configuration loaded successfully through `minfwm reload`.
A controlled comparison of
threshold values has not been performed live. The LaunchAgent lacked
Accessibility permission in this session, so the validated daemon ran directly.
AX notification registration returned `-25207`, and some windows reported
restore failures during daemon shutdown; these remain separate live issues.

The same day, `yabai -m query` showed Ghostty at 1166×704 points on a
1352×878-point display. Those dimensions passed the old 80% eligibility rule;
the new 90% rule rejects them in a geometry regression test while retaining
snap for a 1352×804-point window. The rebuilt daemon started with the new
rule. After restarting the daemon, the user repeated the gesture and confirmed
that Ghostty no longer triggers snap.

The repository's October 2026 development notes report successful lifecycle v2
fixture checks for translation cleanup and process-exit recovery, plus manual
confirmation of ordinary-window pickup/drop and subsequent panning with hybrid
native/transform positioning. These checks do not establish broad desktop
compatibility. Overview has known desktop regressions and an unresolved
one-frame flash; production uses the compatible non-atomic handoff. Treat
popups, multi-display overview, third-party dragging, and complete SA replacement
as unverified until checked on the target Mac.

On 2026-10-15, `minfwm dev-update` was run three times against a foreground daemon.
Each run built the CLI, saved the layout, stopped the socket-owning daemon, and
started a new process; the IPC readiness check verified the new PID. The final
`minfwm status` reported `running (foreground PID 24356)`, and the daemon log
reported layout restoration and `Daemon is running`. The complete 13-test CTest
suite passed on the dirty checkout. Window interaction after the restart was
not checked manually.

Record new live results here with macOS version, hardware, exact extension
capabilities, steps, and outcome. Do not mark unavailable checks as passed.
