# Getting started

## Requirements

- macOS 14 or newer, AppleClang, C++20, and CMake 3.20 or newer.
- Accessibility permission for `minfwm`.
- Disabled System Integrity Protection (SIP).
- The compatible [Yabai Scripting Addition](https://github.com/snusxd/minfwm/wiki/Yabai-Integration) built and loaded separately; the Homebrew formula does not install it.

## Build and run

```sh
cmake -S . -B build -DCMAKE_OSX_DEPLOYMENT_TARGET=14.0
cmake --build build --parallel
ctest --test-dir build --output-on-failure
./build/minfwm daemon
```

Grant Accessibility permission in System Settings, then restart the daemon.
For per-user login startup, run:

```sh
./build/minfwm enable
```

Useful commands:

```sh
./build/minfwm start
./build/minfwm stop
./build/minfwm restart
./build/minfwm dev-update
./build/minfwm disable
./build/minfwm reload
./build/minfwm camera move --x 100 --y 0
```

`start`, `stop`, and `restart` control the current user's LaunchAgent.
`dev-update` saves the current virtual window layout and camera, then restarts
the daemon next to the invoked CLI binary.
`disable` prevents login startup and stops it. The daemon socket is
`$TMPDIR/minfwm.sock`, owned by the current user with mode `0600`.

## Controls

- Super and left-drag pans the canvas.
- Moving three fingers on the trackpad pans the canvas and continues with
  decaying momentum after you lift them.
- Super and vertical scroll zooms the display under the pointer when a
  compatible overview extension is available.
- Clicking a window while zoomed restores normal scale and centers it.
- Escape exits overview; its return anchor is configurable.
- Cmd+1…9 loads a camera bookmark; Cmd+Shift+1…9 saves one.
- Super+P pins or unpins the focused window.
- Super+F centers the camera on the focused window.
- Super+S centers the focused window in the camera.

See [Configuration](https://github.com/snusxd/minfwm/wiki/Configuration) for the supported options.
