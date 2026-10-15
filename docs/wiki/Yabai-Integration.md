# Yabai Scripting Addition Integration

`minfwm` relies on a patched version of the **Yabai Scripting Addition (SA)** to manage windows beyond the standard macOS screen boundaries.

---

## Why Is This Needed?

By default, macOS WindowServer strictly confines application windows to the usable screen area:
- Windows cannot normally be positioned above the top menu bar or far outside the visible screen.
- macOS Accessibility APIs alone cannot smoothly translate or scale windows for aerial canvas overviews.

The Yabai Scripting Addition injects lightweight code into macOS WindowServer/Dock. `minfwm` uses its patched transform support to move and scale windows beyond normal screen bounds and its pinned-level support to keep pinned and temporarily maximized windows above other windows. The daemon checks both capabilities during startup and exits if the loaded addition is incompatible.

---

## Prerequisites: Disabling SIP

Because macOS protects system processes, loading any Scripting Addition requires disabling System Integrity Protection (SIP):

1. Shut down your Mac.
2. Boot into macOS Recovery (hold the Power button on Apple Silicon, or `Cmd + R` on Intel Macs).
3. Open **Utilities → Terminal** from the menu bar.
4. Run the following command:
   ```sh
   csrutil disable
   ```
   *(Or for minimal SIP configuration, see Yabai's documentation on configuring specific SIP flags).*
5. Restart your Mac.

---

## Building and Loading the Scripting Addition

`minfwm` includes an automated script that checks out the compatible Yabai version, applies the required transform patches, and builds the addition locally.

1. Stop `minfwm` if it is currently running:
   ```sh
   minfwm stop
   ```

2. Build and load the Scripting Addition. Use the repository's build script so it fetches the compatible Yabai source and applies the `minfwm` patches:
   ```sh
   python3 tools/build_yabai_sa.py
   sudo ./build/yabai-minfwm/bin/yabai --load-sa
   ```

   > [!NOTE]
   > Loading the Scripting Addition will briefly restart the macOS Dock. This is normal.

   If the daemon reports that transform or pinned-level support is unavailable, verify that the patched binary and addition were built and loaded from this checkout. A standard, unpatched Yabai addition does not satisfy the required handshake.

3. Start `minfwm`:
   ```sh
   minfwm start
   ```

To ensure `minfwm` starts automatically after reboots, configure your system to load the Scripting Addition on boot (as described in the official Yabai documentation, via `sudoers` and `launchd`).

---

## Uninstallation / Reverting

If you wish to remove the custom Scripting Addition:

```sh
minfwm stop
sudo ./build/yabai-minfwm/bin/yabai --uninstall-sa
```

---

## Notes & Known Limitations

- **Dock Restarts**: Loading or updating the Scripting Addition restarts the Dock process.
- **System Dialogs**: Certain native macOS sheets and alert dialogs are bound to their parent applications and follow standard macOS positioning.
- **Overview Zoom**: Overview zoom scales down windows visually. Clicking any window returns to 1:1 scale and centers the view.
- **Temporary Fullscreen**: The shortcut uses the target application's native Fill action and requires macOS 15+ plus an app that exposes that command. It is separate from the Yabai transforms; camera pan or zoom restores the saved window frame.
