# macOS infinite window manager
A window manager for macOS in the style of VXWM or DriftWM, with a primary focus on creating an infinite desktop canvas.

## Dependencies
* **macOS** (Apple Silicon / ARM64 recommended).
* **Yabai Scripting Addition (SA)**: required for smooth window movement above the menu bar and layer management. Requires partially disabled SIP.
* **Accessibility permissions**: the application needs access to accessibility features to manage windows.
* **CMake and C++20**: to build the project.

## Development
Building the project:
```bash
mkdir build && cd build
cmake ..
make
```

Running:
```bash
./minfwm
```

Core components:
* `WindowManager`: A singleton that manages the camera state and the window pool.
* `Camera`: Controls the viewport position and scaling.
* `DisplayManager`: Responsible for physically moving windows via AXAPI or Yabai SA.
* `WindowPool`: Stores and updates the list of active applications and their windows.

## Installation
TODO

## Roadmap
* [x] Initialization of `CFRunLoop` and the `CGEventTap` event system.
* [x] Canvas panning via `Cmd + Option + Drag`.
* [x] Integration with Yabai SA for layer management and bypassing menu bar restrictions.
* [x] Initialization of windows without forced relayout.
* [ ] Tiling Engine: refining `GridLayout` and adding new layout strategies.
* [ ] Keyboard Navigation: camera and window control via keyboard.
* [ ] IPC & CLI: creating `minfwmc` to control the daemon via a socket.
