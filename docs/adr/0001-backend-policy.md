# ADR 0001: Public API First, Optional Yabai SA

## Status

Accepted for phase one.

## Decision

`AXUIElement`, `AXObserver`, `CGEventTap`, `NSWorkspace`, and `CFRunLoop` are
the default macOS integration surface. A small `WindowBackend` interface owns
window move, resize, layer, and restore operations. `AXBackend` is always
available and is the fallback for every failed optional operation.

`YabaiSABackend` is disabled unless it completes a compatible handshake and
each packet receives a valid acknowledgement. It never becomes a startup
requirement and it never owns hide/show policy. Phase one does not implement
native Spaces or new UX features.

## Rationale

The public Accessibility API keeps the daemon usable on macOS 14+ without
disabling SIP. AeroSpace documents virtual workspace emulation by moving
windows, which matches the infinite-canvas model. Yabai's scripting addition
adds privileged capabilities but requires extra installation and SIP caveats.

## Consequences

The AX path must handle accessibility errors and restore state during orderly
shutdown. SA compatibility is tested with golden packets and fault injection;
live SA and WindowServer tests remain manual-only.
