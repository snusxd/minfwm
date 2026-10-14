# Getting started

## Requirements

- macOS 14 or newer, AppleClang, C++20, and CMake 3.20 or newer.
- Accessibility permission for `minfwmd`.
- Yabai is optional; the baseline does not require SIP changes.

## Build and run

```sh
cmake -S . -B build -DCMAKE_OSX_DEPLOYMENT_TARGET=14.0
cmake --build build --parallel
ctest --test-dir build --output-on-failure
./build/minfwmd
```

Grant Accessibility permission in System Settings, then restart the daemon.
For per-user login startup, keep `minfwmd` beside `minfwm` and run:

```sh
./build/minfwm enable
```

Useful commands:

```sh
./build/minfwm start
./build/minfwm stop
./build/minfwm restart
./build/minfwm disable
./build/minfwm reload
./build/minfwm camera move --x 100 --y 0
```

`start`, `stop`, and `restart` control the current user's LaunchAgent.
`disable` prevents login startup and stops it. The daemon socket is
`$TMPDIR/minfwm.sock`, owned by the current user with mode `0600`.

## Controls

- Cmd+Option and left-drag pans the canvas.
- Cmd+Option and vertical scroll zooms the display under the pointer when a
  compatible overview extension is available.
- Clicking a window while zoomed restores normal scale and centers it.
- Escape exits overview; its return anchor is configurable.
- Cmd+1…9 loads a camera bookmark; Cmd+Shift+1…9 saves one.
- Cmd+Option+P pins or unpins the focused window.

See [Configuration](Configuration.md) for the supported options.
