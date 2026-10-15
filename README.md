# minfwm

![minfwm preview](docs/images/preview.png)

`minfwm` is an infinite 2D window canvas for macOS 14+. It turns your desktop into an endless virtual workspace that seamlessly spans across all connected displays.

> [!WARNING]
> This project is completely vibecoded.

## Installation & Quick Start

> [!IMPORTANT]
> `minfwm` requires the custom Yabai Scripting Addition to position windows beyond standard display boundaries. Setup requires disabling SIP; see the [Yabai Integration Guide](https://github.com/snusxd/minfwm/wiki/Yabai-Integration).

### Install via Homebrew

```sh
brew install snusxd/minfwm/minfwm
```

### Enable & Start

1. Grant `minfwm` Accessibility permission in **System Settings → Privacy & Security → Accessibility**.
2. Enable and start the background service:

```sh
minfwm enable
minfwm status
```

*(If the daemon starts before Accessibility permission is granted, it will wait and start automatically once granted).*

### Useful Commands

| Command | Action |
| --- | --- |
| `minfwm status` | Check if the daemon is running |
| `minfwm start` / `stop` / `restart` | Control the background daemon |
| `minfwm reload` | Reload `~/.config/minfwm/minfwm.toml` |
| `minfwm list displays` | List connected displays |
| `minfwm camera move --x 100 --y 0` | Pan the camera via CLI |
| `minfwm disable` | Disable auto-start on login and stop the daemon |

## Build from Source

```sh
cmake -S . -B build -DCMAKE_OSX_DEPLOYMENT_TARGET=14.0
cmake --build build --parallel
ctest --test-dir build --output-on-failure
```

For foreground testing: `./build/minfwm daemon`.

During active development, run `./build/minfwm dev-update` to rebuild the binary, preserve open window positions, and smoothly restart the daemon.

## Features & Documentation

- **[FEATURES.md](FEATURES.md)**: Overview of all built-in features and gestures.
- **[Project Wiki](https://github.com/snusxd/minfwm/wiki)**: Full guides for configuration, shortcuts, architecture, and development.
