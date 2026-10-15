# Overview preview implementation handoff

The distant overview now uses frozen window thumbnails after capture and parking
succeed. Focused, whitelisted, pinned, dragged, auxiliary and selected-return
windows remain live. `zoom.overview-previews` controls the mode; direct overview
interaction (`rewind-on-focus = false`) keeps windows live.

The mode enters at 45% and exits at 55%. ScreenCaptureKit captures one window at a
time with at least 50 ms between launches. Source snapshots are at most 512 pixels
on their longest edge, with a 64 MiB image cache and reusable CALayers on a
nonactivating canvas per display. Missing Screen Recording permission, capture
errors, parking errors and budget exhaustion preserve live fallback. No automatic
permission prompt or screenshots on disk are introduced. The budget covers cached
images, not total process/GPU/canvas memory. Applications continue running.

## Files and ownership

The adapter worker supplied `src/daemon/OverviewPreview.hpp`,
`src/daemon/OverviewPreview.mm`, `src/core/OverviewPreviewPolicy.hpp` and
`tests/OverviewPreviewTests.mm` in an isolated worktree. Root integrated CMake,
configuration, window-manager/renderer lifecycle and hit testing, self-observation
exclusion, tests and documentation in another isolated worktree. The original
checkout was changing concurrently and its unrelated work was left intact.

## Verification

```sh
cmake -S . -B build -DCMAKE_OSX_DEPLOYMENT_TARGET=14.0
cmake --build build --parallel
ctest --test-dir build --output-on-failure
```

Configure/build passed and all 14 tests passed. Three focused preview, renderer
and config targets passed. There is an existing AppKit deprecation warning for
`NSApplicationActivateIgnoringOtherApps`. The adapter worker reported a standalone
strict ARC/macOS 14 build and ASan/UBSan checks passed. Independent review passed
with zero actionable findings and reran the three focused binaries successfully.

The fake-backend workload verifies 100 parking operations across 60 frames for
100 preview originals, compared with 6,000 live overview updates. It measures
command counts only. There is no measured desktop speedup or frame-rate claim.

## Manual acceptance still pending

See `docs/Acceptance-macos.md`, distant preview checklist. In particular,
ScreenCaptureKit framing of already SA-scaled windows, canvas/live stacking,
negative-origin and mixed-density display rendering, actual input targeting,
permission revocation, hide/unhide, reload/shutdown and display reconnection need
live evidence. Use `MINFWM_TRACE_OVERVIEW=1` to collect manager callback time,
live-update counts, cache bytes and captures, with previews off/on for identical
window counts/navigation. Instruments is needed for asynchronous capture and GPU/
WindowServer work. This implementation is not an accepted live release yet.

No daemon was started/restarted and no permissions or SIP settings were changed.
The task is held at Test pending manual acceptance. The task runtime/bootstrap
limitation is recorded in `docs/ai/tasks/TASK-OVERVIEW-PREVIEWS.md`.

## Main integration

User requested integration directly into `main`. The latest committed bookmark
focus behavior is retained alongside overview diagnostics. Existing uncommitted
working changes are preserved separately from this merge. Live acceptance remains
pending; this integration does not start or restart the daemon.
