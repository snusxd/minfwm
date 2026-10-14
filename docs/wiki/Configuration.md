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
zoomed-esc-center = "screen"

[display]
multi-display-mode = "isolated"

[keybinds]
super = ["Cmd", "Alt"]
center-camera-to-focus = ["Super", "F"]
center-focus-to-camera = ["Super", "S"]
```

| Key | Default | Meaning |
| --- | --- | --- |
| `enable-window-shadows` | `false` | Enable managed window shadows. |
| `overscan-buffer-px` | `500` | Physical margin for retaining nearby windows. |
| `whitelist` | `["Terminal", "Music"]` | Applications whose windows remain available. |
| `spawn-behavior` | `"center"` | Placement policy for newly observed windows. |
| `invert-zoom-scroll-direction` | `false` | Reverse vertical-scroll zoom direction. |
| `zoomed-esc-center` | `"screen"` | Escape anchor: `screen`, `mouse`, or `focus`. |
| `multi-display-mode` | `"isolated"` | Camera coordination policy for displays. |
| `keybinds.super` | `["Cmd", "Alt"]` | `Super` modifier chord for pan, zoom, and pin. Supported values: `Cmd`, `Alt`, `Shift`, `Ctrl`. |
| `keybinds.center-camera-to-focus` | `["Super", "F"]` | Move the camera to center the focused window. |
| `keybinds.center-focus-to-camera` | `["Super", "S"]` | Move the focused window to the center of the camera. |

In shortcuts, `Super` means the modifier chord configured here. The two center
shortcuts accept `Super` followed by one uppercase letter from `A` to `Z`. By
default, `Super` is `Cmd+Alt`.

Click selection always centers the selected window; `zoomed-esc-center` only
controls Escape. Changing settings takes effect after `./build/minfwm reload`.
The full example is in `config/minfwm.toml.example` in the source repository.
