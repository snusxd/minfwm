---
paths:
  - "src/daemon/**"
  - "tests/*.mm"
  - "tools/build_yabai_sa.py"
---

# Daemon (`src/daemon/`)

- Positioning beyond the visible frame (above the menu bar, far off-screen) and overview scaling go through the Yabai SA transform (`YabaiSA.mm`), not AX. macOS clamps an AX position back under the menu bar, so an AX write is never the mechanism for off-screen placement.
- Pinned and temporarily maximized windows use the SA pinned-level capability. Both capabilities are verified at startup; missing either aborts.
- Temporary Fullscreen uses the app's native Fill action (macOS 15+, when the app exposes it). The daemon saves the previous frame and restores it on camera pan or zoom; it does not reimplement the Fill animation.
- A user drag can move ownership between managed displays or release a window onto an ignored display; keep ownership changes in one place (`WindowManager`) so renderer and pool stay consistent.
- Overview capture (ScreenCaptureKit, `OverviewPreview.mm`, ARC) is optional: without Screen Recording access or on capture failure, windows stay live. Focused, pinned, whitelisted, selected, auxiliary and dragged windows always stay live.
- Every AX, CG and SA call result is checked; CF values are held by `CFRAII.hpp` wrappers.
