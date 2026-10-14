# Yabai integration

Yabai's Scripting Addition (SA) is required. The daemon checks its version and
capability handshake and refuses to start unless transform and pinned-level
support are available. The stock SA cannot guarantee placement above the menu
bar; use the compatible extension built below.

## Experimental extension

The repository contains a pinned Yabai 7.1.25 extension with lifecycle v2
translation and overview capabilities. Build it locally:

```sh
python3 tools/build_yabai_sa.py
sudo ./build/yabai-minfwm/bin/yabai --load-sa
```

Disable System Integrity Protection before setup. Stop the daemon with
`minfwm stop` before loading. This replaces the installed Yabai SA and may
restart Dock. To revert, stop the daemon with `minfwm stop`, uninstall using
the original Yabai `--uninstall-sa`, then load the original `--load-sa`. An SA
unload may leave transforms in WindowServer, so confirm normal native dragging
before restarting the daemon.

The daemon automatically uses compatible lifecycle v2 translation for
above-menu-bar/offscreen placement. Overview additionally needs a newer
capability set. The production overview handoff uses the compatible move/reset
path; an atomic handoff remains limited to the isolated fixture. This feature is
experimental: desktop movement, one-frame flashes, popups/dialogs, multi-display
behavior, and third-party native dragging have outstanding manual checks.

Use [the current macOS acceptance checklist](https://github.com/snusxd/minfwm/wiki/Acceptance-macos#macos-acceptance).
