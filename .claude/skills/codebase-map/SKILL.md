---
name: codebase-map
description: Where things live in minfwm — a task-to-directory map plus a lookup for which rule files cover a path. Use at the start of a task, before grepping or listing directories to find the code to change.
---

# Codebase map

Read this instead of re-exploring the tree. Architecture and invariants are in `AGENTS.md` (= `CLAUDE.md`) and `docs/wiki/Architecture.md`; per-area rules are in `.claude/rules/`.

```bash
python3 .claude/skills/codebase-map/rules_for.py <path>...   # the rule files that apply to each path
```

Run it on every file you plan to edit and read what it prints. Claude Code auto-injects those rules on the first Read, but not after /compact until a matching file is read again, and other agents never get them.

## Where a task goes

| Task | Start here | Then |
|------|-----------|------|
| Canvas geometry, camera math, projection | `src/core/{Geometry,Camera}.*` | `tests/GeometryTests.cpp` |
| Visibility / culling policy | `src/core/Visibility.*` | `src/daemon/WindowRenderer.mm` |
| Per-display state, negative origins | `src/core/DisplayState.*` | `src/daemon/WindowManager.mm` |
| Pan / pinch gestures | `src/core/PanGesture.*` | `src/daemon/{TrackpadInput,InputInterceptor}.mm` |
| Window drag, clipped title bars, ownership | `src/core/{WindowDrag,WindowOwnership,NativeWindowInteraction}.hpp` | `src/daemon/WindowManager.mm`, `tests/WindowInteractionTests.mm` |
| Window discovery, AX events, focus | `src/daemon/{AXObserver,AXBackend}.mm` | `WindowPool.mm`, `BookmarkFocus.hpp` |
| Applying transforms / off-screen placement | `src/daemon/{WindowRenderer,WindowPosition}.mm` | backend `YabaiSA.mm`, interface `WindowBackend.hpp` |
| Yabai SA handshake, packets, patches | `src/daemon/YabaiSA.mm` | `tools/build_yabai_sa.py`, `tests/{YabaiSATests,TransformPayloadTests}.*` |
| Keyboard shortcuts, event tap | `src/daemon/InputInterceptor.mm` | config keys in `ConfigManager.mm` |
| Overview previews (ScreenCaptureKit) | `src/daemon/OverviewPreview.mm` | `src/core/OverviewPreviewPolicy.hpp` |
| Config (TOML), reload | `src/daemon/ConfigManager.mm` | `config/`, `docs/wiki/Configuration.md`, `tests/ConfigTests.mm` |
| Daemon lifecycle, run loop, frame clock | `src/daemon/{main,DaemonRunLoop,DisplayFrameClock}.mm` | `AccessibilityPermission.hpp` |
| CLI commands | `src/cli/CommandLine.cpp` | `src/cli/{IPCClient,DaemonControl}.mm` |
| Wire protocol, socket | `src/common/Protocol.hpp`, `LocalSocketListener.*` | `src/daemon/IPCServer.mm`, `tests/IPC*` |
| Build, tests | `CMakeLists.txt` | `.github/workflows/ci.yml` |

## Not project code

`build/`, `third_party/` (read, don't edit), `.cache/`.
