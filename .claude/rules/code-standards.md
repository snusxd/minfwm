# Code Standards

## Design Philosophy

- **Prefer the robust, long-term fix.** Address race conditions, error states and boundary cases (negative display origins, display hot-plug, a window closing mid-operation) in the first implementation.
- **Reuse existing patterns.** Check `src/core/` and the daemon adapters before adding a new helper or a second model of the same state.
- **State transformations live in `src/core/`.** Platform calls stay at the Objective-C++ adapter boundary in `src/daemon/`; `src/core/` never includes AppKit, Core Graphics, Accessibility or SkyLight headers, so it stays headless-testable.

## C++ / Objective-C++

- C++20, four spaces, `PascalCase` types, `lowerCamelCase` methods, `m_` members.
- **RAII for every owned resource**: Core Foundation values through `src/daemon/CFRAII.hpp`, file descriptors through `src/common/UniqueFd.hpp`. No bare `CFRelease` / `close` pairs on new code paths.
- **Check every result**: each `AXError`, socket call and SA reply is checked; a failure is logged once where it is finally handled, not at every layer.
- Main-thread discipline: AppKit, Accessibility and window presentation updates run on the main thread; only screenshot capture completes asynchronously.

## GUI / Menus (Swift)

- **GUI menus and interfaces are written in Swift** (SwiftUI / AppKit), not in C++ or Objective-C++.
- Keep GUI code decoupled from the C++/Objective-C++ daemon hot path: talk to the daemon through the versioned IPC socket (`src/common/Protocol.hpp`) so UI work cannot block `CGEventTap` or WindowServer updates.

## Contracts

- `src/common/Protocol.hpp` is the versioned wire contract between CLI and daemon. A change there needs a focused CTest first (malformed frames, partial I/O) and a version decision.
- Config reload is atomic: invalid TOML keeps the last valid snapshot.
- Startup aborts when the Yabai SA handshake or a required capability (transform, pinned level) is missing. Never add a silent fallback.
- Daemon exit clears every WindowServer transform and restores native positions.

## Testing

- Add a focused CTest before changing a wire or pure-core contract (`tests/`, dependency-free, registered in `CMakeLists.txt`).
- Accessibility, WindowServer, CGEventTap and live SA behaviour are manual-only: record them with `docs/Acceptance-macos.md`, and say in the handoff what the owner must check by hand. Never claim a manual check as passed.
