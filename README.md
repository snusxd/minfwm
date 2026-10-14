# minfwm

`minfwm` is an infinite 2D window canvas for macOS 14 and newer. It places
windows on a virtual desktop that spans connected displays. The default backend
uses macOS Accessibility APIs and does not require SIP changes; a compatible
Yabai Scripting Addition is optional.

## Build and start

```sh
cmake -S . -B build -DCMAKE_OSX_DEPLOYMENT_TARGET=14.0
cmake --build build --parallel
ctest --test-dir build --output-on-failure
```

Grant `minfwmd` Accessibility permission in System Settings. For a foreground
run, start `./build/minfwmd` in one terminal. In another terminal, control it
with `minfwm`:

```sh
./build/minfwm enable
./build/minfwm status
./build/minfwm camera move --x 100 --y 0
```

`enable` installs and starts the per-user LaunchAgent. Other lifecycle commands
are `start`, `stop`, `restart`, `disable`, and `reload`. Keep `minfwmd` beside
`minfwm` when using the LaunchAgent. The daemon socket is
`$TMPDIR/minfwm.sock`, owned by the current user with mode `0600`.

## Controls

- Hold Super and drag with the left mouse button to pan the canvas.
- Hold Super and scroll vertically to zoom the display under the pointer
  when the compatible overview extension is available.
- Click a window while zoomed to restore normal scale and center it.
- Press Escape to exit overview. The return anchor is configurable.
- Press Cmd+1…9 to load a camera bookmark; Cmd+Shift+1…9 saves one.
- Press Super+P to pin or unpin the focused window.

## Configuration and documentation

The optional configuration file is `~/.config/minfwm/minfwm.toml`. Copy
[`config/minfwm.toml.example`](config/minfwm.toml.example) to get started; reload
settings with `./build/minfwm reload`. Invalid configuration keeps the last
valid settings active. The `[pins]` option `always-on-top` controls whether
pinned windows stay above other windows.

See the [project Wiki](https://github.com/snusxd/minfwm/wiki) for the complete
[getting-started guide](https://github.com/snusxd/minfwm/wiki/Getting-Started),
[configuration reference](https://github.com/snusxd/minfwm/wiki/Configuration),
[architecture](https://github.com/snusxd/minfwm/wiki/Architecture),
[development guide](https://github.com/snusxd/minfwm/wiki/Development), and
[macOS acceptance checks](https://github.com/snusxd/minfwm/wiki/Acceptance-macos).
