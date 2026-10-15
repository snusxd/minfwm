# Development Guide

This guide covers building `minfwm` from source, running tests, and developing locally.

---

## Prerequisites

- macOS 14 (Sonoma) or newer
- Xcode Command Line Tools (AppleClang with C++20 support)
- CMake 3.20 or newer

---

## Build from Source

Clone the repository and build using CMake:

```sh
cmake -S . -B build -DCMAKE_OSX_DEPLOYMENT_TARGET=14.0
cmake --build build --parallel
```

The compiled binary will be placed at `./build/minfwm`.

---

## Running Automated Tests

`minfwm` includes a test suite powered by CTest. Run all automated tests with:

```sh
ctest --test-dir build --output-on-failure
```

### Focused Test Suites

You can build and run individual test suites for faster development iterations:

| Area | Build Target | Run Command |
| --- | --- | --- |
| **Core Geometry & Snap** | `cmake --build build --target minfwm_geometry_tests` | `ctest --test-dir build -R geometry` |
| **IPC & Protocol** | `cmake --build build --target minfwm_ipc_tests` | `ctest --test-dir build -R ipc` |
| **Yabai SA Integration** | `cmake --build build --target minfwm_yabai_sa_tests` | `ctest --test-dir build -R yabai` |

---

## Rapid Local Iteration with `dev-update`

When making changes to the daemon or CLI, use the built-in `dev-update` command:

```sh
./build/minfwm dev-update
```

To follow the daemon log after the update, pass `--attach`:

```sh
./build/minfwm dev-update --attach
```

Attach prints the most recent 20 log lines and follows new output. Press `Ctrl-C`
to detach from the log; the daemon continues running.

What `dev-update` does:
1. Rebuilds the `minfwm` binary in your `build` directory.
2. Captures and saves your current window positions and camera locations.
3. Gracefully restarts the running daemon.
4. Restores all windows and cameras back to where they were.

This allows seamless code iterations without having windows scatter across your screen on every rebuild.

---

## Code Style & Conventions

- **C++ Standard**: C++20.
- **Indentation**: 4 spaces, no tabs.
- **Naming**: `PascalCase` for types and classes, `lowerCamelCase` for functions and methods, and `m_` prefix for private member variables.
- **Architecture**: Keep pure math and geometry algorithms in `src/core/`; keep macOS and AppKit API interactions strictly within `src/daemon/`.
- **Manual Verification**: Since Accessibility, WindowServer, and trackpad gestures interact with the live operating system, see [docs/Acceptance-macos.md](../../docs/Acceptance-macos.md) for manual verification steps.
