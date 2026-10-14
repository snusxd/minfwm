# minfwm

![minfwm preview](docs/images/preview.png)

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

## Features and documentation

See [FEATURES.md](FEATURES.md) for a quick overview of implemented features.
For setup, configuration, and detailed guides, visit the
[project Wiki](https://github.com/snusxd/minfwm/wiki).
