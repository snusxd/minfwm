# Overview previews

Goal: reduce per-window presentation work at distant zoom by replacing eligible
live windows with bounded, frozen thumbnails. Focused, whitelisted, pinned,
dragged and auxiliary windows stay live. Applications remain running.

1. Research: existing overview uses one acknowledged SA transform and position
   check per changed window. No live performance baseline has been measured.
   ScreenCaptureKit supplies single-window screenshots on macOS 14+.
2. Build: introduce a hysteresis policy (enter <=45%, leave >=55%), asynchronous
   single-flight capture, 512-pixel thumbnails and a 64 MiB image budget, with a
   nonactivating canvas per display. Preserve live presentation until capture
   and parking succeed. At the user's request, enabled previews request missing
   capture permission once per daemon run and preserve live fallback after denial.
3. Integrate: add `zoom.overview-previews`, preserve previews for direct overview
   interaction, keep model geometry when parking originals, select thumbnails
   through the same displayed scene, and release canvases on shutdown/reload.
4. Review: independently inspect asynchronous ownership, error fallback,
   restoration, hit testing, display coordinates, and the task-only diff.
5. Test: focused pure policy/config/renderer/adapter tests, then full CTest at
   integration. Add opt-in timings and operation counts for manual profiling.
6. Acceptance: permission denial, live whitelist/focus, multi-display origins,
   selection/Escape, reload/shutdown, and actual performance remain manual until
   measured on a desktop with compatible SA. Do not mark visible behavior Done
   solely from mocked tests.

The starting checkout has unrelated uncommitted changes. Root integrates without
staging or committing them. The adapter worker owns only its four new files in
an isolated worktree; root exclusively owns shared integration files.
