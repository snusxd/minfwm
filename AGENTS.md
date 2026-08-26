# Repository Guidelines

## Project Structure
- `src/core/` contains pure C++20 geometry, camera, display-state, and visibility policy code.
- `src/daemon/` contains the Objective-C++ `minfwmd` adapter: AX observers, event tap, backends, config, lifecycle, and IPC server.
- `src/cli/` contains `minfwmc`; `src/common/Protocol.hpp` owns the versioned wire contract.
- `tests/` contains dependency-free C++/Objective-C++ CTest targets. `docs/` contains ADRs, research, and the acceptance matrix.
- `.agents/skills/` is a pinned, selected AAS subset. Do not add the full catalog.

## Build, Test, and Development Commands
```bash
cmake -S . -B build -DCMAKE_OSX_DEPLOYMENT_TARGET=14.0
cmake --build build --parallel
ctest --test-dir build --output-on-failure
./build/minfwmd
./build/minfwmc reload
./build/minfwmc camera move --x 100 --y 0
```
- `minfwmd` requires Accessibility permission. Yabai SA is optional; the AX backend must work without SIP changes.
- The Unix socket is created as `$TMPDIR/minfwm.sock` with user ownership and mode `0600`.

## File-Scoped Commands
| Task | Command |
| --- | --- |
| Core tests | `cmake --build build --target minfwm_geometry_tests && ctest --test-dir build -R geometry` |
| IPC/CLI tests | `cmake --build build --target minfwm_ipc_tests && ctest --test-dir build -R ipc` |
| Backend tests | `cmake --build build --target minfwm_yabai_sa_tests && ctest --test-dir build -R yabai` |

## Coding Style & Naming
- Use four spaces, C++20, `PascalCase` types, `lowerCamelCase` methods, and `m_` members.
- Keep platform calls at Objective-C++ adapter boundaries; keep state transformations in `src/core/`.
- Use RAII for sockets and Core Foundation values. Check every AX, socket, and SA result.

## Testing Guidelines
- Add a focused CTest before changing a wire or pure-core contract. Test malformed frames, partial I/O, invalid config, negative display origins, lifecycle idempotence, and SA packet bytes.
- Accessibility, WindowServer, CGEventTap, and live SA checks are manual-only; record them using `docs/acceptance-macos.md`.

## Commits and Pull Requests
- Use Conventional Commit subjects: `type: short English summary` (`fix: reject malformed IPC frame`).
- PRs must describe behavior and ownership changes, list build/CTest and macOS manual checks, link an issue when available, and include screenshots or recordings for visible window behavior.

## Security and Configuration
- Preserve atomic config reload: invalid TOML keeps the last valid snapshot.
- Treat Yabai SA as an optional, handshake-checked optimization; failed move/layer/ACK operations must reach AX fallback.
- Do not commit credentials, machine-specific paths, SIP changes, or live socket files.
