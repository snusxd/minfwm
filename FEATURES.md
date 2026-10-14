# Features

- Manage windows on an infinite 2D desktop using macOS Accessibility APIs.
- Pan the camera by dragging, zoom with scroll when compatible overview support
  is available, and move the camera to exact coordinates from the CLI.
- Keep independent camera positions on multiple displays, including displays
  with negative coordinate origins.
- Center the camera on the focused window or move the focused window to the
  camera center with configurable shortcuts.
- Save and restore up to nine camera positions with keyboard shortcuts.
- Pin or unpin the focused window and optionally keep pinned windows above
  others.
- Choose how new windows are placed, keep selected apps available, and configure
  window shadows and the offscreen retention margin.
- Configure scroll direction, Escape return position, and how cameras coordinate
  across displays.
- Discover windows as apps launch or close, and restore captured window geometry
  when the daemon exits.
- Start, stop, restart, enable or disable login startup, and reload configuration
  from the CLI; invalid configuration leaves the last valid settings active.
- Use a compatible Yabai Scripting Addition for experimental presentation
  transforms and overview zoom; the [acceptance checklist](https://github.com/snusxd/minfwm/wiki/Acceptance-macos#macos-acceptance)
  tracks remaining manual checks.
