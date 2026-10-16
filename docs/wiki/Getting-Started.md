# Getting Started

This guide walks you through setting up and using `minfwm`.

## Prerequisites

1. **macOS 14 (Sonoma) or newer**.
2. **Disabled System Integrity Protection (SIP)**: Required to load the custom Yabai Scripting Addition.
3. **Compatible Yabai Scripting Addition (SA)**: Provides low-level window transforms for smooth offscreen positioning. Follow the [Yabai Integration Guide](https://github.com/snusxd/minfwm/wiki/Yabai-Integration) to build and load it.
4. **Accessibility Permission**: `minfwm` needs Accessibility access to track windows and mouse/keyboard events.

Screen Recording permission is optional. Grant it if you want static thumbnails for distant windows in overview mode (`[zoom] overview-previews = true`, the default). Without access, the daemon continues with live windows. See [Configuration](https://github.com/snusxd/minfwm/wiki/Configuration) for preview behavior and troubleshooting.

---

## Installation

### Option 1: Homebrew (Recommended)

Install the latest release via Homebrew:

```sh
brew install snusxd/minfwm/minfwm
```

### Option 2: Build from Source

Requirements: AppleClang, C++20, and CMake 3.20+.

```sh
cmake -S . -B build -DCMAKE_OSX_DEPLOYMENT_TARGET=14.0
cmake --build build --parallel
ctest --test-dir build --output-on-failure
```

The resulting binary will be located at `./build/minfwm`.

---

## Initial Setup & Permissions

1. **Grant Accessibility Permission**:
   - Open **System Settings → Privacy & Security → Accessibility**.
   - Add and enable `minfwm` (or your terminal application if running manually).
   - If the daemon starts before permissions are granted, it will automatically detect the permission once granted without needing a restart.

2. **Enable Background Service**:
   Register and start the daemon as a user LaunchAgent:

   ```sh
   minfwm enable
   ```

   To check that it is running:

   ```sh
   minfwm status
   ```

---

## CLI Management

Control the `minfwm` daemon easily from your terminal:

| Command | Description |
| --- | --- |
| `minfwm status` | Check whether the daemon is currently running and its PID. |
| `minfwm start` | Start the background daemon. |
| `minfwm stop` | Stop the background daemon and restore windows to original positions. |
| `minfwm restart` | Restart the background daemon. |
| `minfwm reload` | Reload configuration from `~/.config/minfwm/minfwm.toml` on the fly. |
| `minfwm list displays` | List connected displays and their names (useful for display configuration). |
| `minfwm enable` | Register and start `minfwm` to launch automatically at login. |
| `minfwm disable` | Stop `minfwm` and disable auto-start on login. |
| `minfwm camera move --x <px> --y <px>` | Move the active camera by a specific pixel offset. |
| `minfwm dev-update [--attach]` | (Developers) Rebuilds the binary, preserves window positions, restarts the daemon, and optionally attaches to logs. |

---

## Default Controls & Gestures

> [!NOTE]
> By default, **`Super`** is set to **`Cmd + Option`** (`Cmd + Alt`). You can customize this chord in your [Configuration](https://github.com/snusxd/minfwm/wiki/Configuration).

### Canvas Navigation

- **Three-Finger Swipe**: Pan the canvas smoothly in any direction (features natural decay momentum).
- **`Super` + Left-Click Drag**: Pan the canvas with your mouse.
- **Four-Finger Pinch**: Zoom out to an overview of your canvas.
- **`Super` + Scroll Wheel**: Zoom in or out.
- **Click Window in Overview**: Zooms back into 100% scale and centers on that window.
- **`Escape`**: Exit overview zoom mode.

### Window Management

- **`Super + Ctrl` + Drag** (or three-finger swipe): **Drag Everywhere** — move a window without needing to grab its title bar. Dragging a clipped title bar also lets you bring that window back onto the display.
- **`Super + Ctrl + F`**: **Temporary Fullscreen** — invokes the app's native Fill action (macOS 15+); panning or zooming the camera restores the window's previous frame. This works when the app exposes the system Fill command.
- **`Super + P`**: Pin or unpin the currently focused window (pinned windows stay on screen as you pan).
- **`Super + F`**: Center the camera onto the currently focused window, returning to 100% zoom if zoomed out.
- **`Super + S`**: Pull the focused window to the center of the current camera view.
- **`Cmd + Tab`**: Automatically moves the camera to center the newly focused application window.

### Camera Bookmarks

Save your favorite canvas locations and jump between them instantly (bookmarks save both camera position and active window focus):

- **`Super + 1..9`**: Save the current camera position and focused window to slot 1–9.
- **`Super + Shift + 1..9`**: Jump immediately to saved slot 1–9.
