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

The `[keybinds]` section is reserved and does not configure shortcuts. Click
selection always centers the selected window; `zoomed-esc-center` only controls
Escape. Changing settings takes effect after `./build/minfwm reload`. The full
example is in `config/minfwm.toml.example` in the source repository.
