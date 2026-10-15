# minfwm

![minfwm preview](docs/images/preview.png)

`minfwm` is an infinite 2D window canvas for macOS. It places windows on a virtual desktop that spans connected displays.

> [!WARNING]
> This project is completely vibecoded.

## Installation and usage

> [!IMPORTANT]
> Install the compatible Yabai Scripting Addition separately. Setup requires disabling SIP; see the [Yabai integration guide](https://github.com/snusxd/minfwm/wiki/Yabai-Integration).

Install the latest stable release from the to macOS 14+
[Homebrew tap](https://github.com/snusxd/homebrew-minfwm):

```sh
brew install snusxd/minfwm/minfwm
```

Grant `minfwm` Accessibility permission in System Settings, then enable the
per-user LaunchAgent:

```sh
minfwm enable
minfwm status
minfwm camera move --x 100 --y 0
```

If the daemon starts before Accessibility is enabled, it stays running and
rechecks the permission until macOS grants it; a daemon restart is not needed.

Use `minfwm start`, `stop`, or `restart` to control the daemon. In a source
checkout, `./build/minfwm dev-update` builds the `minfwm` target first, saves the
current virtual window layout and camera when the daemon is running, restarts the
daemon, and waits for its IPC readiness response. A build or startup failure returns
a nonzero status. The LaunchAgent executable needs Accessibility permission;
startup errors from the daemon log are reported by `dev-update`.
When a foreground `minfwm daemon` owns the IPC socket, `dev-update` saves its
layout, stops it, and starts the rebuilt daemon in the background. Otherwise it
restarts the LaunchAgent. Readiness is checked against the new daemon's PID.
`minfwm reload`
applies configuration changes; `minfwm disable` stops the daemon and removes
login startup.

## Build from source

```sh
cmake -S . -B build -DCMAKE_OSX_DEPLOYMENT_TARGET=14.0
cmake --build build --parallel
ctest --test-dir build --output-on-failure
```

For a foreground run, start `./build/minfwm daemon`. The daemon socket is
`$TMPDIR/minfwm.sock`, owned by the current user with mode `0600`.

## Features and documentation

See [FEATURES.md](FEATURES.md) for a quick overview of implemented features.
For setup, configuration, and detailed guides, visit the
[project Wiki](https://github.com/snusxd/minfwm/wiki).
