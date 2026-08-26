# Multi-Agent Refactor Plan

The integration branch is `codex/refactor-integration`. Each worker owns a
disjoint worktree and returns a commit plus local validation evidence. The
integrator is the only writer of cross-cutting build files and final docs.

| Packet | Owner | Files | Dependency | Acceptance |
| --- | --- | --- | --- | --- |
| A | Architect | `docs/adr/`, contracts | none | ADRs define wire, backend, thread, and ownership rules |
| B | IPC/CLI | `src/common/`, `src/cli/`, `IPCServer.*`, IPC tests | A | framing, partial I/O, errors, safe CLI exit codes |
| C | Core | `src/core/`, `WindowPool.*`, geometry tests | A | pure model tests, negative origins, idempotent lifecycle |
| D | Backends | `AXBackend.*`, `YabaiSA.*`, backend tests | C | handshake, golden packets, timeout/ACK fallback |
| E | Runtime/config | `AXObserver.*`, `InputInterceptor.*`, `ConfigManager.*`, `main.mm` | C | main-thread dispatch, atomic reload, stop/restore |
| F | QA/reviewer | read-only review and sanitizer report | B-E | findings, threat model, residual manual checks |
| G | Integrator | `CMakeLists.txt`, docs, merge | all required packets | build, CTest, acceptance matrix |

The join rule is `all_required`: a packet is integrated only after its owned
files, tests, and commit are reviewed. Late or duplicate results are ignored
after the integrator records the accepted commit. Live Accessibility,
WindowServer, and SA checks remain manual macOS acceptance tests.
