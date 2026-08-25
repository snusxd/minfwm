# Repository Guidelines

## Project Structure
- `src/daemon/` contains the `minfwmd` Objective-C++ daemon: window management, camera state, accessibility observers, input interception, configuration, and IPC server code.
- `src/cli/` contains the `minfwmc` command-line IPC client.
- `src/common/Protocol.hpp` defines messages shared by the daemon and CLI.
- `CMakeLists.txt` defines both executables and links the required macOS frameworks. `build/` is generated and ignored.

## Package Manager
- No package manager or lockfile is used. Build with CMake, AppleClang, C++20, and the system Apple frameworks.

## Build, Test, and Development Commands
```bash
cmake -S . -B build
cmake --build build
./build/minfwmd
./build/minfwmc
```
- The binaries require macOS, Accessibility permission, and Yabai Scripting Addition for the supported window-management paths. Yabai SA may require partially disabled SIP.
- There is no automated test target or coverage requirement. After building, manually smoke-test daemon startup, CLI-to-daemon IPC, window movement, and camera behavior on macOS.

## File-Scoped Commands
| Task | Command |
| --- | --- |
| Build daemon | `cmake --build build --target minfwmd` |
| Build CLI | `cmake --build build --target minfwmc` |

## Coding Style & Naming
- Use four-space indentation and the existing C++20/Objective-C++ style; keep code in the `minfwm` namespace.
- Use `PascalCase` for types, `lowerCamelCase` for methods and local variables, and `m_` prefixes for members.
- Keep declarations in `.hpp` files and implementations in `.mm` files. No formatter or linter is configured, so preserve surrounding style and verify with the CMake build.

## Commit & Pull Request Guidelines
- Recent history favors short `<type>: <summary>` subjects such as `feat:` and `fix:`; use a concise imperative summary and keep unrelated changes separate.
- Pull requests should explain behavior or architecture changes, list macOS validation performed, link an issue when applicable, and include screenshots or recordings for visible window-management changes.

## Commit Attribution
- AI-authored commits must include a `Co-Authored-By:` trailer with the agent's actual model name and attribution address.

## Security & Configuration
- Do not commit credentials, local socket details, or machine-specific configuration. Review `src/daemon/ConfigManager.*` before changing configuration behavior, and document any new permission or SIP requirements.
