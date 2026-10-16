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

[bookmarks]
save-focus = true

[keybinds]
super = ["Cmd", "Alt"]
center-camera-to-focus = ["Super", "F"]
center-focus-to-camera = ["Super", "S"]
temporarily-fullscreen = ["Super", "Ctrl", "F"]
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
| `rewind-on-focus` | `true` | When zoomed out, clicking a window exits overview and focuses that window. If `false`, clicking a thumbnail restores and focuses its live window at the current zoom; subsequent clicks interact with it normally. This option does not disable previews. |
| `overview-previews` | `true` | Show static preview thumbnails for distant windows in overview mode to improve performance. Requires Screen Recording permission. |
| `zoomed-esc-center` | `"screen"` | Camera target when pressing `Escape` to exit overview: `"screen"`, `"mouse"`, or `"focus"`. |

> [!TIP]
> **Overview Previews**: When zooming far out, `minfwm` can display lightweight preview thumbnails for background windows instead of continuously rendering live windows. Active and pinned windows always stay live. With previews enabled, the daemon requests missing Screen Recording permission once when it starts rendering displays, independently of `rewind-on-focus`. If access is denied, overview keeps all windows live. Enable previously denied access in System Settings → Privacy & Security → Screen Recording; macOS may require restarting the daemon after granting it.

With `rewind-on-focus = false`, the first click on a thumbnail selects it and
promotes its original to a live window without changing the camera or scale.
That selection click is consumed, including its mouse-up, so it cannot activate
a control or another application underneath the thumbnail. Further clicks and
typing go to the selected live window; the previously focused window can become
a thumbnail. With `rewind-on-focus = true`, selection retains the return to 100%.

Overview diagnostics use the `OverviewPreview:` prefix in the daemon log
(`~/Library/Logs/minfwm.log` when launched by `minfwm start` or `dev-update`).
Permission and mode changes are logged once. `first-snapshot-ready` confirms
capture succeeded; `first-preview-shown` immediately reports the first replacement,
including during short overview sessions. `shown=N` reports how many originals were replaced
by previews in that display frame. Changed counts, cache bytes, captures and
failures are reported at most once per second. Capture errors include the stage,
macOS error domain/code and live fallback, with repeated errors limited to once
per five seconds. Window IDs are logged; window titles and contents are omitted.
`WindowRenderer: preview-parking-failed` identifies backend failures that keep a
captured window live, also limited to once per five seconds.
`preview-session-ended` and `cache-released` report return to live presentation
and release of cached snapshots. These logs confirm the code path, not image
quality or a measured performance improvement.

Set `MINFWM_TRACE_OVERVIEW=1` when launching the daemon for additional `OVERVIEW`
timings and live-update counts once per second during overview.

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

### `[bookmarks]`

| Key | Default | Description |
| --- | --- | --- |
| `save-focus` | `true` | Save the focused window with each bookmark and restore focus when jumping to it. Set to `false` to save camera position only. |

---

### `[keybinds]`

Modifiers can include: `"Cmd"`, `"Alt"` (Option), `"Shift"`, `"Ctrl"`, and `"Super"`.

| Key | Default | Description |
| --- | --- | --- |
| `super` | `["Cmd", "Alt"]` | Modifier chord representing the `Super` key throughout `minfwm`. |
| `center-camera-to-focus` | `["Super", "F"]` | Shortcut to center the focused window; when zoomed out, it also returns the camera to 100% zoom. |
| `center-focus-to-camera` | `["Super", "S"]` | Shortcut to move the focused window to the center of your screen. |
| `temporarily-fullscreen` | `["Super", "Ctrl", "F"]` | Use the native macOS Fill command (macOS 15+); camera movement or zoom restores the previous frame. The app must expose the system Fill menu item. |
| `drag-everywhere` | `["Super", "Ctrl"]` | Modifiers to hold while dragging any part of a window to move it. |
| `bookmarks-add` | `["Super"]` | Modifiers to hold with digits 1–9 to save a camera bookmark slot (e.g. `Super + 1`). |
| `bookmarks-goto` | `["Super", "Shift"]` | Modifiers to hold with digits 1–9 to jump to a saved bookmark (e.g. `Super + Shift + 1`). |
