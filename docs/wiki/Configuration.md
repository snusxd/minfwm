# Configuration

`minfwm` is configured via a TOML file located at:

```
~/.config/minfwm/minfwm.toml
```

If the file does not exist, all default settings are used.

To apply changes, run:

```sh
minfwm reload
```

> [!TIP]
> **Atomic Reload**: If the configuration contains any syntax errors or invalid values, `minfwm reload` will reject the changes and keep your existing settings active without interrupting your session.

---

## Example `minfwm.toml`

```toml
[window]
enable-window-shadows = false
overscan-buffer-px = 500
whitelist = ["Terminal", "Music"]
spawn-behavior = "center"

[camera]
center-on-cmd-tab = true
mouse-movement-multiplier = 1.0
trackpad-movement-multiplier = 1.0
trackpad-invert-x = false
trackpad-invert-y = false

[snap]
enable = true
threshold = 32
vertical-tuning = "auto"
horizontal-tuning = "auto"

[zoom]
invert-zoom-scroll-direction = false
track-invert-zoom-direction = false
rewind-on-focus = true
overview-previews = true
zoomed-esc-center = "screen"

[pins]
always-on-top = true

[animations]
enable = true
speed = 1.0

[display]
multi-display-mode = "isolated"
ignored-displays = []

[keybinds]
super = ["Cmd", "Alt"]
center-camera-to-focus = ["Super", "F"]
center-focus-to-camera = ["Super", "S"]
drag-everywhere = ["Super", "Ctrl"]
bookmarks-add = ["Super"]
bookmarks-goto = ["Super", "Shift"]
```

---

## Configuration Reference

### `[window]`

| Key | Default | Description |
| --- | --- | --- |
| `enable-window-shadows` | `false` | Enable or disable system window shadows for managed windows. |
| `overscan-buffer-px` | `500` | Margin (in pixels) around the visible screen where offscreen windows remain loaded. |
| `whitelist` | `["Terminal", "Music"]` | List of application names whose windows are never hidden when offscreen. |
| `spawn-behavior` | `"center"` | Placement policy for newly created windows (`"center"` places them in the current camera view). |

---

### `[camera]`

| Key | Default | Description |
| --- | --- | --- |
| `center-on-cmd-tab` | `true` | Automatically center the camera on the newly focused window after switching apps with `Cmd + Tab`. |
| `mouse-movement-multiplier` | `1.0` | Pan speed factor for `Super` + mouse drag (`2.0` is twice as fast, `0.5` is half speed). |
| `trackpad-movement-multiplier` | `1.0` | Pan speed factor for three-finger trackpad panning. |
| `trackpad-invert-x` | `false` | Invert horizontal trackpad panning direction. |
| `trackpad-invert-y` | `false` | Invert vertical trackpad panning direction. |

---

### `[snap]`

Snapping automatically eases large windows into place along display borders when panning gestures stop.

| Key | Default | Description |
| --- | --- | --- |
| `enable` | `true` | Enable edge snapping for near-fullscreen windows (covering at least 90% of screen size). |
| `threshold` | `32` | Distance in screen points from a display edge within which snapping triggers (range: `0`–`1000`). |
| `vertical-tuning` | `"auto"` | Vertical placement: `"auto"` (nearest edge), `"top"`, `"center"`, or `"bottom"`. |
| `horizontal-tuning` | `"auto"` | Horizontal placement: `"auto"` (nearest edge), `"left"`, `"center"`, or `"right"`. |

---

### `[zoom]`

| Key | Default | Description |
| --- | --- | --- |
| `invert-zoom-scroll-direction` | `false` | Invert zoom direction when scrolling with `Super` + scroll wheel. |
| `track-invert-zoom-direction` | `false` | Invert four-finger trackpad pinch zoom direction independently. |
| `rewind-on-focus` | `true` | When zoomed out, clicking a window exits overview and focuses that window. If `false`, clicks interact directly with the scaled window. |
| `overview-previews` | `true` | Replace eligible distant overview windows with frozen thumbnails after capture succeeds. Requires existing Screen Recording permission and `rewind-on-focus = true`; otherwise windows remain live. |
| `zoomed-esc-center` | `"screen"` | Camera target when pressing `Escape` to exit overview: `"screen"`, `"mouse"`, or `"focus"`. |

Previews start at 45% scale or below and return to live windows at 55% or above.
Focused, whitelisted, pinned, dragged, selected-return and auxiliary windows stay
live. Live windows appear above the preview canvas. Preview contents remain frozen
for the distant overview session; the applications continue running in the
background. This reduces presentation work, rather than unloading applications.

Capture launches at most once per 50 ms, with one screenshot in flight. Thumbnails
are limited to 512 pixels on the longest edge and a total 64 MiB image cache. A
pending/failed capture or exhausted cache keeps the affected window live. Images
are kept in memory and released when every display leaves preview mode, on display
refresh, or at shutdown. No screenshot files are saved.

The daemon checks Screen Recording access without requesting it. Grant access
manually in System Settings if desired; missing permission does not prevent
startup or ordinary live overview. Live macOS acceptance of this mode is pending.

For manual profiling, launch the daemon with `MINFWM_TRACE_OVERVIEW=1`. Once per
second during overview it reports `OVERVIEW` lines with average/maximum manager
update time, live presentation updates, preview draws, capture counts, and image
bytes. Compare identical navigation with `overview-previews = false` and `true`.
These timings cover the manager callback, not asynchronous capture, GPU frame
completion or total WindowServer work; use Instruments for the latter.

---

### `[pins]`

| Key | Default | Description |
| --- | --- | --- |
| `always-on-top` | `true` | Keep pinned windows (`Super + P`) floating above all other non-pinned windows. |

---

### `[animations]`

| Key | Default | Description |
| --- | --- | --- |
| `enable` | `true` | Enable smooth animations for camera panning, zooming, and snapping. |
| `speed` | `1.0` | Animation speed multiplier (range: `0.1` to `10.0`). Set higher for snappier animations, lower for smoother transitions. |

---

### `[display]`

| Key | Default | Description |
| --- | --- | --- |
| `multi-display-mode` | `"isolated"` | Multi-monitor mode. Each connected display has its own independent 2D canvas. |
| `ignored-displays` | `[]` | List of display names to leave unmanaged (run `minfwm list displays` to view available names). Ignored displays behave like regular macOS screens. |

---

### `[keybinds]`

Modifiers can include: `"Cmd"`, `"Alt"` (Option), `"Shift"`, `"Ctrl"`, and `"Super"`.

| Key | Default | Description |
| --- | --- | --- |
| `super` | `["Cmd", "Alt"]` | Modifier chord representing the `Super` key throughout `minfwm`. |
| `center-camera-to-focus` | `["Super", "F"]` | Shortcut to pan the camera to center the focused window. |
| `center-focus-to-camera` | `["Super", "S"]` | Shortcut to move the focused window to the center of your screen. |
| `drag-everywhere` | `["Super", "Ctrl"]` | Modifiers to hold while dragging any part of a window to move it. |
| `bookmarks-add` | `["Super"]` | Modifiers to hold with digits 1–9 to save a camera bookmark slot (e.g. `Super + 1`). |
| `bookmarks-goto` | `["Super", "Shift"]` | Modifiers to hold with digits 1–9 to jump to a saved bookmark (e.g. `Super + Shift + 1`). |
