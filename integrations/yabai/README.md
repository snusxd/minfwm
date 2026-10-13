# Absolute window translation extension

Pinned upstream: Yabai 7.1.25, commit
`02de172f8706c3e2eaa679478897d7346e82b564` (MIT).

Build with `python3 tools/build_yabai_sa.py`. This does not install anything.
The resulting `build/yabai-minfwm/bin/yabai --load-sa` must be run with sudo
from a terminal to install/load the payload. It replaces the installed Yabai
scripting addition; it does not change SIP. Loading can restart Dock.
Transforms are experimental and selected automatically with lifecycle v2. The first revision caused
persistent offsets in third-party windows. Lifecycle v2 passed fixture and
ten-application coordinate/exit checks. With hybrid native/transform positioning,
the user also confirmed that native dragging after panning no longer jumps at
pickup or on the next pan. Popups and multiple displays still need acceptance
checks; see `docs/acceptance-macos.md` for the scope of each result.

The payload retains upstream's 2.1.29 bundle version so the existing 7.1.25
`dock_did_restart` loader preserves it. A separate bundle identifier lets the
custom installer distinguish it from stock SA and lifecycle v1:
`com.minfwm.yabai-sa.overview3`. Upgrading Yabai may replace the
extension; the daemon then falls back to ordinary moves until it is reloaded.
To revert, uninstall the SA with the original Yabai's `--uninstall-sa`, then
load the original Yabai's `--load-sa`. Stop minfwmd first. Unloading an SA alone
does not clear any transforms already left in WindowServer; confirm normal
native dragging before restarting minfwmd.

The patched handshake is numeric version `2.1.29` with attributes `0x780`:
`0x80` for absolute translation and `0x100` for lifecycle v2 cleanup.
Both lifecycle bits and the exact version are required for translation.
`0x200` additionally advertises overview scaling; all three bits are required
for opcode `0x16`. `0x400` additionally advertises atomic native handoff
(opcode `0x17`); it requires all earlier capabilities. A lifecycle v2 payload without `0x200` remains compatible
with translation and native movement. Lifecycle v1 (`0x80` alone) is rejected. Integers are
little endian; all packets retain Yabai's uint16 payload-length prefix.

| Opcode | Payload after opcode | Reply |
| --- | --- | --- |
| `0x14` | WID u32, owner PID u32, x i32, y i32 | byte 0 success, 1 failure |
| `0x15` | WID u32, owner PID u32 | byte 0 success, 1 failure |
| `0x16` | WID u32, owner PID u32, x i32, y i32, scale u32 | byte 0 success, 1 failure |
| `0x17` | WID u32, owner PID u32, x i32, y i32 | byte 0 success, 1 failure |

`0x14` sets an absolute translation at scale 1 without moving AppKit's frame.
It captures the prior level once per window, accepts only an untransformed
native baseline, validates the exact packet length and peer PID, and limits
coordinates to ±16000. The daemon additionally verifies WindowServer bounds.
`0x15` clears translation relative to the current native frame, restores the
captured level and is idempotent. A frame changed by native dragging must not
be reset using the old frame's translation.

`0x16` sets absolute position and uniform presentation scale in integer
thousandths, bounded to 200–1000 (20–100%). WindowServer receives the inverse
matrix `(1/s, 0, 0, 1/s, -x/s, -y/s)`. It shares ownership, recovery entries,
explicit ACKs, coordinate limits and reset/watchdog cleanup with translation.
Application native size is unchanged. The daemon blocks application input in
overview; selection returns to unit scale before native interaction.

`0x17` hands an owned window back to native geometry in one request. It blocks
presentation updates while moving the native frame, associating geometry and
restoring a unit transform, and always reenables updates on failure. It preserves
the current layer and retains ownership for final reset/process-death cleanup.
Older payloads keep the separate move/reset fallback. A live probe of that
fallback exposed an intermediate displaced frame; atomic handoff prevents it
from being presented.

Desktop validation subsequently reported broken movement and overview despite
the isolated fixture passing. The production backend therefore uses the prior
`0x06` then `0x15` handoff even when `0x400` is advertised. Atomic handoff is
explicitly enabled only by the isolated `--overview-fixture` tool. Run
`--overview-compatible-fixture` to check the production path. The one-frame
flash remains unresolved; the isolated success is not desktop acceptance.

On macOS 27, the legacy geometry-association symbol is a bare `ret` with no
defined return value. Its older-system side effect is retained, but it cannot
serve as an error status. Native move, bounds, transform and update-resume
results are checked, followed by client position readback.

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
