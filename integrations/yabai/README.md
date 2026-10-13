# Absolute window translation extension

Pinned upstream: Yabai 7.1.25, commit
`02de172f8706c3e2eaa679478897d7346e82b564` (MIT).

Build with `python3 tools/build_yabai_sa.py`. This does not install anything.
The resulting `build/yabai-minfwm/bin/yabai --load-sa` must be run with sudo
from a terminal to install/load the payload. It replaces the installed Yabai
scripting addition; it does not change SIP. Loading can restart Dock.
Transforms are experimental and selected automatically with lifecycle v2. The first revision caused
persistent offsets in third-party windows; lifecycle v2 is built and unit-tested,
but has not passed the revised live acceptance matrix. Do not treat the earlier
fixture pass as evidence of safe native dragging.

The payload retains upstream's 2.1.29 bundle version so the existing 7.1.25
`dock_did_restart` loader preserves it. A separate bundle identifier lets the
custom installer distinguish it from stock SA and lifecycle v1:
`com.minfwm.yabai-sa.lifecycle2`. Upgrading Yabai may replace the
extension; the daemon then falls back to ordinary moves until it is reloaded.
To revert, uninstall the SA with the original Yabai's `--uninstall-sa`, then
load the original Yabai's `--load-sa`. Stop minfwmd first. Unloading an SA alone
does not clear any transforms already left in WindowServer; confirm normal
native dragging before restarting minfwmd.

The patched handshake is numeric version `2.1.29` with attributes `0x180`:
`0x80` for absolute translation and `0x100` for lifecycle v2 cleanup.
Both bits and the exact version are required before the daemon selects
extension commands. Lifecycle v1 (`0x80` alone) is rejected. Integers are
little endian; all packets retain Yabai's uint16 payload-length prefix.

| Opcode | Payload after opcode | Reply |
| --- | --- | --- |
| `0x14` | WID u32, owner PID u32, x i32, y i32 | byte 0 success, 1 failure |
| `0x15` | WID u32, owner PID u32 | byte 0 success, 1 failure |

`0x14` sets an absolute translation at scale 1 without moving AppKit's frame.
It captures the prior level once per window, accepts only an untransformed
native baseline, validates the exact packet length and peer PID, and limits
coordinates to ±16000. The daemon additionally verifies WindowServer bounds.
`0x15` clears translation relative to the current native frame, restores the
captured level and is idempotent. A frame changed by native dragging must not
be reset using the old frame's translation.

The single socket thread owns all saved state. Every 250 ms it compares process
PID plus start time; if the owning daemon dies, it restores its windows. Failed
restoration remains eligible for retry. Once translation has been cleared,
retrying failed level restoration does not touch geometry again. Socket reads
have a timeout so a stalled
client cannot indefinitely prevent cleanup. This is process-death recovery,
not a heartbeat for a hung daemon.

The regular daemon resets transforms before AX size/visibility operations and
shutdown. It reads visual WindowServer positions when syncing transformed
windows back into the virtual canvas. Stock SA and AX remain supported.

The lifecycle v1 fixture passed continuous translation, clicks, typing and
process-death recovery on macOS 27, but later third-party dragging exposed a
system-wide regression. Lifecycle v2 needs all desktop checks in
`docs/acceptance-macos.md`, including dragging during/after translation, orderly
and unexpected shutdown, SA replacement, sheets/popups and multiple displays.
