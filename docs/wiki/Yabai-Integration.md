# Yabai integration

Yabai's Scripting Addition (SA) is optional. The daemon checks the SA version
and capability handshake; unavailable, incompatible, or failed operations use
Accessibility fallback. Stock SA supports ordinary movement and layering but
cannot guarantee placement above the menu bar.

## Experimental extension

The repository contains a pinned Yabai 7.1.25 extension with lifecycle v2
translation and overview capabilities. Build it locally:

```sh
python3 tools/build_yabai_sa.py
sudo ./build/yabai-minfwm/bin/yabai --load-sa
```

Stop `minfwmd` before loading. This replaces the installed Yabai SA and may
restart Dock; it does not change SIP. To revert, stop minfwmd, uninstall using
the original Yabai `--uninstall-sa`, then load the original `--load-sa`. An SA
unload may leave transforms in WindowServer, so confirm normal native dragging
before restarting the daemon.

The daemon automatically uses compatible lifecycle v2 translation for
above-menu-bar/offscreen placement. Overview additionally needs a newer
capability set. The production overview handoff uses the compatible move/reset
path; an atomic handoff remains limited to the isolated fixture. This feature is
experimental: desktop movement, one-frame flashes, popups/dialogs, multi-display
behavior, and third-party native dragging have outstanding manual checks.

Use [[Acceptance-macos|the current macOS acceptance checklist]].
