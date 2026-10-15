# macOS Acceptance Checklist

Automated headless tests (CTest) verify pure geometry, IPC framing, and configuration logic. However, live macOS features—such as Accessibility observers, Core Graphics event taps, WindowServer transforms, and trackpad gestures—require manual verification on real hardware.

Use this checklist to verify `minfwm` behavior on macOS.

---

## 1. Startup, Permissions & Shutdown

- [ ] **Accessibility Gate**: Start the daemon without Accessibility permission. Confirm it logs waiting state cleanly without crashing.
- [ ] **Permission Grant**: Grant Accessibility access in System Settings while the daemon is waiting. Confirm it automatically starts managing windows without needing a process restart.
- [ ] **Clean Exit**: Stop the daemon (`minfwm stop` or Ctrl+C if foreground). Confirm that all windows hidden or moved by `minfwm` are restored to standard macOS coordinates and transforms are cleared.

---

## 2. Canvas Navigation & Gestures

- [ ] **Three-Finger Pan**: Swipe with three fingers on the trackpad. Confirm the camera pans smoothly and glides to a stop with natural momentum.
- [ ] **Mouse Pan**: Hold `Super` (`Cmd + Option`) and drag with the left mouse button. Confirm the canvas follows cursor movement.
- [ ] **Overview Zoom**: Pinch with four fingers on the trackpad or scroll while holding `Super`. Confirm the view zooms out to show an overview of all windows.
- [ ] **Overview Focus**: While zoomed out, click on any window. Confirm the camera smoothly zooms back in to 100% and focuses that window.
- [ ] **Escape Return**: While zoomed out, press `Escape`. Confirm the view returns to normal scale.

---

## 3. Window Snapping

- [ ] **Near-Fullscreen Snap**: Enlarge a window so it covers 90%+ of the screen width and height. Pan the camera until the window approaches a display edge. Confirm the camera smoothly snaps and eases the window into place.
- [ ] **Interrupted Snap**: Start a new pan gesture during a snap animation. Confirm the gesture immediately takes over smoothly from the visible position.
- [ ] **Small Windows Ignored**: Pan near windows smaller than 90% of the display. Confirm edge snapping is not triggered.

---

## 4. Window Controls & Shortcuts

- [ ] **Drag Everywhere**: Hold `Super + Ctrl` and drag anywhere inside a window (or swipe with three fingers). Confirm the window moves freely without needing to click the title bar.
- [ ] **Bookmark Focus**: Save bookmarks while different windows are focused, switch to other windows, then jump to each bookmark. Confirm keyboard input goes to the window saved in that slot. Repeat with `bookmarks.save-focus = false` and confirm only the camera position changes. Live verification of this scenario is pending.
- [ ] **Temporary Fullscreen**: Press `Super + Ctrl + F` repeatedly on different apps and on a display with a negative origin. Confirm the native macOS Fill command expands the window and minfwm does not interrupt its system animation. Pan or zoom during expansion and after it settles; confirm the original frame is restored. Confirm the maximized window stays above other app windows, and restoration moves left/right edges before top/bottom edges. Confirm its temporary topmost level is cleared on restore. Repeat with animations disabled. Live verification of this scenario is pending.
- [ ] **Window Pinning**: Focus a window and press `Super + P`. Pan the camera. Confirm the pinned window stays visible on screen and floats above other windows.
- [ ] **Center Camera on Focus**: Pan away from the active window and press `Super + F`. Confirm the camera centers on the focused window.
- [ ] **Center Focus on Camera**: Select a partially offscreen window and press `Super + S`. Confirm the window moves to the center of your current screen view.
- [ ] **App Switching**: Switch apps using `Cmd + Tab`. Confirm the camera automatically pans to center the newly active window.

---

## 5. Camera Bookmarks

- [ ] **Save Bookmark**: Position the camera over a set of windows and press `Super + 1`.
- [ ] **Jump to Bookmark**: Pan far away to another part of the canvas, then press `Super + Shift + 1`. Confirm the camera smoothly animates back to the saved position.

---

## 6. Multi-Display Support

- [ ] **Independent Canvases**: On a multi-monitor setup, pan the camera on Display 1. Confirm Display 2 remains stationary.
- [ ] **Negative Display Origins**: Verify correct positioning on secondary displays placed above or to the left of the main display.
- [ ] **Ignored Displays**: Add a monitor name to `display.ignored-displays` in `minfwm.toml` and run `minfwm reload`. Drag a window onto that monitor; confirm it behaves as a standard, unmanaged macOS window.
