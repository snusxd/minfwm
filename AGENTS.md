# Repository Guidelines

## Project Structure
- `src/core/` — pure C++20 geometry, camera, display-state, and visibility policy (no macOS headers).
- `src/daemon/` — Objective-C++ daemon (`minfwm daemon`): AX observers, event tap, Yabai SA backend, config, lifecycle, IPC server.
- `src/cli/` — `minfwm` CLI; `src/common/Protocol.hpp` owns the versioned wire contract.
- `tests/` — dependency-free C++/Objective-C++ CTest targets.
- `docs/wiki/` — project documentation.

## Build, Test, and Development Commands
```bash
cmake -S . -B build -DCMAKE_OSX_DEPLOYMENT_TARGET=14.0
cmake --build build --parallel
ctest --test-dir build --output-on-failure
./build/minfwm daemon
./build/minfwm reload
./build/minfwm camera move --x 100 --y 0
```
- `minfwm daemon` requires Accessibility permission, SIP disabled, and a compatible Yabai SA (transform + pinned-level support).
- Unix socket: `$TMPDIR/minfwm.sock` (user-owned, mode `0600`).

## File-Scoped Commands
| Task | Command |
| --- | --- |
| Core tests | `cmake --build build --target minfwm_geometry_tests && ctest --test-dir build -R geometry` |
| IPC/CLI tests | `cmake --build build --target minfwm_ipc_tests && ctest --test-dir build -R ipc` |
| Backend tests | `cmake --build build --target minfwm_yabai_sa_tests && ctest --test-dir build -R yabai` |

## Agent Rules and Skills
- `.claude/rules/code-standards.md` applies to every task (coding style, RAII, contracts, testing, GUI in Swift).
- Path-scoped rules in `.claude/rules/` (`core.md`, `daemon.md`, `ipc.md`) hold per-area invariants. Outside Claude Code (or after `/compact`), run `python3 .claude/skills/codebase-map/rules_for.py <files to edit>` and read what it prints before editing.
- `.claude/skills/codebase-map/SKILL.md` routes tasks to files; `.claude/agents/minfwm-explorer.md` is the read-only locator.
- Procedures: `commit` (stage by name, no AI attribution) and `sync-rules` (`python3 .claude/skills/sync-rules/check_rules.py` must exit 0).
- New invariants belong in `.claude/rules/`, not here. Preserve the `CLAUDE.md -> AGENTS.md` symlink.

## Commits, PRs, and Workflow
- Conventional Commits: `type: short English summary` (e.g., `fix: reject malformed IPC frame`).
- No AI attribution (`Co-Authored-By` / `AI-Tools`); stage files by name and use plain `git commit`.
- PRs should describe behavior/ownership changes, list build/CTest and manual macOS checks (`docs/Acceptance-macos.md`), and include screenshots/recordings for visible window changes.
- Concurrent writers must use separate Git worktrees. Run the smallest affected check for routine changes, and full CTest at integration checkpoints or before releases. Never claim unavailable manual checks as passed.
