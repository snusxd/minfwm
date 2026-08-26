# macOS Acceptance Matrix

Automated checks run on every integration pass:

```text
cmake -S . -B build -DCMAKE_OSX_DEPLOYMENT_TARGET=14.0
cmake --build build --parallel
ctest --test-dir build --output-on-failure
```

Manual checks on macOS 14+ require Accessibility permission. Verify daemon
startup without Yabai SA, Cmd+Option panning, focused-window behavior, a
secondary display with a negative origin, launch/terminate, `minfwmc reload`,
malformed CLI/config input, and orderly shutdown restoration. Repeat movement
and layering with a compatible Yabai SA installed; confirm handshake failure,
timeout, invalid ACK, and missing socket all fall back to AX without blocking
startup.

Sanitizers apply to the pure C++ core only. Live Accessibility, WindowServer,
CGEventTap, and SA behavior cannot be proven by portable tests and must be
reported separately from automated results.
