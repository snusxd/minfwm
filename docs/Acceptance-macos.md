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
- [ ] **Distant Preview Entry**: With Screen Recording already granted, set `[zoom] overview-previews = true`. Zoom below 45% with many windows; thumbnails should replace eligible windows gradually. Focus, whitelist, pinned and auxiliary windows stay live. Check that captures of transformed windows contain correctly framed content without transparent padding, distortion or blank images. This live check is pending.
- [ ] **Preview Vertical Coordinates**: Pan up and down in distant overview. Thumbnails must move in the same direction as live windows, appear at matching top/bottom positions and become live at the same position when selected. Check clipped thumbnails and displays above/below the primary display, including after resizing/recreating the canvas. Automated adapter tests cover both movement directions, screen edges, clipping and negative display origins; live verification is pending.
- [ ] **Preview Thresholds**: Move repeatedly between 45% and 55%; confirm stable mode within that band, live restoration at 55%, and no jump in window geometry. Check simultaneous pan and zoom, including partly clipped thumbnails.
- [ ] **Preview Selection and Drag**: Select overlapping thumbnails, including a thumbnail under a live window; confirm the visibly topmost target is selected. Try `Super + Ctrl` dragging a thumbnail; confirm it becomes live and follows the initial pointer offset. Click-to-return and `Escape` must restore originals without ghost canvases.
- [ ] **Preview Permission Request**: Start without Screen Recording access with previews enabled, testing both `rewind-on-focus` values. Confirm macOS receives a permission request once, even before zooming out. Deny it and confirm startup continues with live windows and no repeated request across frames, displays, zoom sessions or reloads. Already-granted access and disabled previews must not trigger a request. Enable previously denied access in System Settings; confirm access is detected, restarting the daemon if macOS requires it. Live verification is pending.
- [ ] **Preview Selection without Rewind**: Set `rewind-on-focus = false`, zoom below 45%, and select a thumbnail. Confirm the original becomes live and receives keyboard focus at unchanged scale/camera; the selection down/up must not click through. Select another thumbnail and confirm the old focus can return to a preview. Subsequent clicks on the focused live window must work normally. Check overlapping live, preview and unmanaged windows, secondary buttons, pan/drag modifiers, hide/close during selection, failed restoration/focus and `Escape`. Repeat with rewind enabled and confirm return to 100% is preserved. Live verification is pending.
- [ ] **Preview Fallback**: Deny/revoke Screen Recording access and disable `overview-previews` via reload. Confirm live windows remain usable and startup succeeds without capture permission. Failed capture/parking and an exhausted cache must leave affected windows live.
- [ ] **Preview Lifecycle**: Close, hide/unhide and focus apps during distant overview. Reconfigure/reconnect displays, including negative origins, ignored displays and Retina/non-Retina displays. Reload and shut down while thumbnails are visible; confirm all original windows restore and canvases disappear.
- [ ] **Preview Performance**: Record identical pan/zoom traces with previews off/on at fixed window counts and scales. Use `MINFWM_TRACE_OVERVIEW=1` for callback time/live-update counts/image bytes and Instruments for frame hitches, asynchronous capture, GPU/WindowServer work and memory. Include entry capture cost, steady navigation and return to live. No speedup has yet been measured.
- [ ] **Preview Diagnostics**: Confirm `OverviewPreview:` logs report permission changes, live/preview mode, the first snapshot, `first-preview-shown` even during short sessions, actual `shown` counts, cache release and capture-error stage/domain/code. Confirm `WindowRenderer: preview-parking-failed` identifies failed original-window parking. Repeated unchanged frames must stay quiet; changed summaries are limited to once per second and repeated errors to once per five seconds. Match `shown` counts to the visible desktop. Live verification is pending.

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
