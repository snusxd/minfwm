# ADR 0003: Main-Thread State and RAII Ownership

## Status

Accepted for phase one.

## Decision

Accessibility/AppKit state changes are serialized through one main-thread
executor. IPC and system callbacks only validate input and enqueue work. Pure
geometry, camera, visibility, and display calculations remain independent of
Objective-C++ so they can be tested without WindowServer.

Core Foundation values returned by copy/create APIs are owned by explicit RAII
wrappers. `WindowPool` owns one record per AX reference/WID and keeps identity
indexes synchronized on add/remove. Shutdown stops producers before releasing
observers, restores window geometry, then removes the IPC socket.

## Consequences

Callbacks cannot race mutable window state, and tests can cover lifecycle and
negative display origins on any host. Live Accessibility behavior still needs
manual macOS acceptance because no fake can prove WindowServer behavior.
