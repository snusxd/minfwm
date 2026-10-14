# minfwm

`minfwm` is an infinite 2D window canvas for macOS 14+. It maps virtual window
positions onto connected displays; native macOS Spaces are not used. The default
backend uses Accessibility APIs and does not require SIP changes. A compatible
Yabai Scripting Addition is optional.

## Build

```sh
cmake -S . -B build -DCMAKE_OSX_DEPLOYMENT_TARGET=14.0
cmake --build build --parallel
ctest --test-dir build --output-on-failure
./build/minfwmd
```

Grant `minfwmd` Accessibility permission in System Settings. In another terminal:

```sh
./build/minfwm enable
./build/minfwm camera move --x 100 --y 0
```

`enable` installs the per-user LaunchAgent and starts the daemon. See the
[Wiki](https://github.com/snusxd/minfwm/wiki) for configuration, commands,
architecture, development, and manual macOS checks.
