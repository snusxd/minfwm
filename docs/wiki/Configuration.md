# Configuration

The optional file is `~/.config/minfwm/minfwm.toml`. Reload is atomic: invalid
input leaves the last valid settings active. Older root-level keys remain
accepted.

```toml
[window]
enable-window-shadows = false
overscan-buffer-px = 500
whitelist = ["Terminal", "Music"]
spawn-behavior = "center"

[zoom]
invert-zoom-scroll-direction = false
rewind-on-focus = true
zoomed-esc-center = "screen"

[camera]
center-on-cmd-tab = true
mouse-movement-multiplier = 1.0
trackpad-movement-multiplier = 1.0
trackpad-invert-x = false
trackpad-invert-y = false

[display]
multi-display-mode = "isolated"

[keybinds]
super = ["Cmd", "Alt"]
center-camera-to-focus = ["Super", "F"]
center-focus-to-camera = ["Super", "S"]
drag-everywhere = ["Super", "Ctrl"]
bookmarks-add = ["Super"]
bookmarks-goto = ["Super", "Shift"]
```

| Key | Default | Meaning |
| --- | --- | --- |
| `enable-window-shadows` | `false` | Enable managed window shadows. |
| `overscan-buffer-px` | `500` | Physical margin for retaining nearby windows. |
| `whitelist` | `["Terminal", "Music"]` | Applications whose windows remain available. |
| `spawn-behavior` | `"center"` | Placement policy for newly observed windows. |
| `invert-zoom-scroll-direction` | `false` | Reverse vertical-scroll zoom direction. |
| `rewind-on-focus` | `true` | When zoomed, clicking a window exits overview and returns the camera. When `false`, clicks and other input pass through to windows while the camera stays zoomed. |
| `camera.center-on-cmd-tab` | `true` | Center the camera on the active application's focused window after switching apps with `Cmd+Tab`. |
| `zoomed-esc-center` | `"screen"` | Escape anchor: `screen`, `mouse`, or `focus`. |
| `camera.mouse-movement-multiplier` | `1.0` | Scale camera movement while dragging: `2.0` moves twice as far as the cursor; `0.5` moves half as far. Must be finite and non-negative. |
| `camera.trackpad-movement-multiplier` | `1.0` | Scale camera movement while panning with three fingers on the trackpad. Must be finite and non-negative. |
| `camera.trackpad-invert-x` | `false` | Reverse horizontal camera movement for three-finger trackpad panning. |
| `camera.trackpad-invert-y` | `false` | Reverse vertical camera movement for three-finger trackpad panning. |
| `multi-display-mode` | `"isolated"` | Camera coordination policy for displays. |
| `keybinds.super` | `["Cmd", "Alt"]` | `Super` modifier chord for pan, zoom, and pin. Supported values: `Cmd`, `Alt`, `Shift`, `Ctrl`. |
| `keybinds.center-camera-to-focus` | `["Super", "F"]` | Move the camera to center the focused window. |
| `keybinds.center-focus-to-camera` | `["Super", "S"]` | Move the focused window to the center of the camera. |
| `keybinds.drag-everywhere` | `["Super", "Ctrl"]` | Hold these modifiers and left-drag any point in a window to move it. |
| `keybinds.bookmarks-add` | `["Super"]` | Save the current camera position in the bookmark selected by the pressed digit. |
| `keybinds.bookmarks-goto` | `["Super", "Shift"]` | Return to the bookmark selected by the pressed digit. |

In shortcuts, `Super` means the modifier chord configured here. The two center
shortcuts accept `Super` followed by one uppercase letter from `A` to `Z`.
Bookmark bindings configure modifiers only; the pressed digit selects bookmark
1 through 9. By default, `Super` is `Cmd+Alt`, so `Super+1..9` saves bookmarks
and `Super+Shift+1..9` returns to them. Bookmark modifier arrays accept unique
`Super`, `Cmd`, `Alt`, `Shift`, and `Ctrl` values.

With `rewind-on-focus = true`, clicking a window while zoomed exits overview and
centers the selected window. With it disabled, clicks and other input pass
through to windows while the camera stays zoomed. The independent
`camera.center-on-cmd-tab` option controls camera centering when switching apps.
`zoomed-esc-center` controls the Escape anchor when rewind-on-focus is enabled.
Changing settings takes effect after `./build/minfwm reload`.
The full example is in `config/minfwm.toml.example` in the source repository.
