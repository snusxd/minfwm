# Architecture

## Boundaries

- `src/core/` contains platform-independent C++20 geometry, cameras, display
  state, and visibility policy.
- `src/daemon/` adapts Accessibility, Core Graphics events, AppKit, run loops,
  configuration, lifecycle, IPC, and the required Yabai backend.
- `src/cli/` implements `minfwm`; `src/common/Protocol.hpp` owns the wire format.

Display bounds use one physical coordinate system and may have negative
origins. Platform adapters convert native screen coordinates at the boundary.
AppKit and Accessibility state changes run on the main thread; IPC workers
validate requests and enqueue commands.

## Window presentation

Each display has a camera over virtual window coordinates. The daemon projects
visible windows into physical display coordinates and parks or hides other
windows according to the configured policy. Shutdown restores captured native
position and size, unhides windows hidden by the daemon, and clears owned
presentation transforms when possible.

Native positioning is used in the usable screen area. The required extension
translates rendered windows outside it while preserving native input geometry.
Position readback detects application frame corrections; persistently
constrained positions are rejected.

## IPC

The local `MFWM` version-1 protocol uses a little-endian command and payload
length. Payloads are capped at 64 bytes. The Unix socket is
`$TMPDIR/minfwm.sock`, owned by the current user with mode `0600`; a lock file
prevents a second daemon from replacing the active socket. Invalid CLI input
returns a nonzero status.

## Decisions

The daemon requires a compatible Yabai Scripting Addition handshake with
transform and pinned-level support. Core geometry stays independent of Apple
APIs. See source history for prior design discussions.
