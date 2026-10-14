# macOS acceptance

Accessibility, WindowServer, CGEventTap, window focus, and live Yabai SA behavior
are manual-only. Build/CTest success does not prove those interactions.

## Checks

- Start with the required Yabai SA; grant and revoke Accessibility permission;
  verify clear errors and orderly startup/shutdown.
- Pan with Super drag; verify focus, pin/unpin, native dragging, and camera
  bookmarks.
- Check a secondary display with a negative origin and independent cameras.
- Verify window visibility, native geometry, and restoration after normal exit.
- Check translation, overview zoom, selection, Escape, application frame
  correction, and process-exit recovery.
- Check popups, sheets/dialogs, multiple displays, dragging during and after
  translation, and behavior when Yabai or the daemon restarts.

## Current evidence

The repository's October 2026 development notes report successful lifecycle v2
fixture checks for translation cleanup and process-exit recovery, plus manual
confirmation of ordinary-window pickup/drop and subsequent panning with hybrid
native/transform positioning. These checks do not establish broad desktop
compatibility. Overview has known desktop regressions and an unresolved
one-frame flash; production uses the compatible non-atomic handoff. Treat
popups, multi-display overview, third-party dragging, and complete SA replacement
as unverified until checked on the target Mac.

Record new live results here with macOS version, hardware, exact extension
capabilities, steps, and outcome. Do not mark unavailable checks as passed.
