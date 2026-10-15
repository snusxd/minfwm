# Repository Guidelines

## Project Structure
- `src/core/` contains pure C++20 geometry, camera, display-state, and visibility policy code.
- `src/daemon/` contains the Objective-C++ daemon implementation, invoked by `minfwm daemon`: AX observers, event tap, backends, config, lifecycle, and IPC server.
- `src/cli/` contains the `minfwm` command-line interface; `src/common/Protocol.hpp` owns the versioned wire contract.
- `tests/` contains dependency-free C++/Objective-C++ CTest targets. `docs/wiki/` contains project documentation.
- `.agents/skills/` is a pinned, selected AAS subset. Do not add the full catalog.

## Build, Test, and Development Commands
```bash
cmake -S . -B build -DCMAKE_OSX_DEPLOYMENT_TARGET=14.0
cmake --build build --parallel
ctest --test-dir build --output-on-failure
./build/minfwm daemon
./build/minfwm reload
./build/minfwm camera move --x 100 --y 0
```
- `minfwm daemon` requires Accessibility permission and a compatible Yabai SA with transform and pinned-level support. SIP must be disabled.
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
- Accessibility, WindowServer, CGEventTap, and live SA checks are manual-only; record them using `docs/Acceptance-macos.md`.

## Commits and Pull Requests
- Use Conventional Commit subjects: `type: short English summary` (`fix: reject malformed IPC frame`).
- PRs must describe behavior and ownership changes, list build/CTest and macOS manual checks, link an issue when available, and include screenshots or recordings for visible window behavior.

## Security and Configuration
- Preserve atomic config reload: invalid TOML keeps the last valid snapshot.
- Abort startup when the required Yabai SA handshake or capabilities are missing.
- Do not commit credentials, machine-specific paths, SIP changes, or live socket files.

## Active AI Workflow
- Start a new chat with `docs/ai/AI-Workflow.md`; open `.agents/skills` guidance only when relevant to the task.
- Bootstrap once per new checkout/tool with `python3 tools/ai_bootstrap.py --tool codex` (use the actual tool ID). Do not repeat bootstrap or profile/task validation every chat unless setup changed or a tool error needs diagnosis. Never silently overwrite an existing hook manager.
- `CLAUDE.md` is the existing symlink to this file; preserve it. Task cards and workflow metadata remain under `docs/ai/` and `.agents/`.
- Keep routine changes fast: one fresh worker when isolation helps, a short prompt with goal/acceptance/owned paths/relevant skill, coordinator integration, and the smallest affected check. Do not add planner, researcher, reviewer or tester agents by default.
- Use task cards and the seven-stage runtime only for multi-step, risky or parallel work. Independent review is risk-triggered or periodic, not a per-change gate. Run full CTest at integration checkpoints and before releases, not after every small edit. Required live macOS evidence still blocks claims that depend on it.
- Concurrent code writers use separate worktrees. Shared contracts, CMake, instructions and integration state have one writer. Do not stage another task's changes.
- `.agents/workflow-stack.json` selects the five supplied skills plus narrow adapters. Load only the role/domain skills. Do not activate competing raw batch-refactor, acceptance-orchestrator or Superpowers lifecycles.
- Register actual AI participants and use `tools/ai-commit --tools codex --task TASK-ID -- -m 'type: English summary'` for managed commits. Direct Git is only a declaration fallback; replacement amend must use the wrapper to preserve participants. Keep human coauthors and never invent official bot identities.
- Run the affected product check for routine changes; run workflow-tool tests when changing workflow tooling. Full CTest and independent review are periodic/release checks or required by elevated risk. Never claim unavailable manual checks or usage as passed/measured.
