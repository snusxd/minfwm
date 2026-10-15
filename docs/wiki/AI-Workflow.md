# Repository AI Workflow

This reference outlines workflow principles for assisted and autonomous development in `minfwm`.

---

## Guidelines

- **Repository Policy**: Defined in [AGENTS.md](../../AGENTS.md) and [GEMINI.md](../../GEMINI.md).
- **Skill Profiles**: Pinned skills are configured under `.agents/workflow-stack.json`.
- **Routine Changes**:
  - Keep iterations lightweight and direct.
  - Provide a clear goal, acceptance criteria, owned paths, and the smallest relevant check.
  - Reserve multi-step task cards (`docs/ai/tasks/`) for complex, multi-agent, or risky tasks.
- **Concurrency & Worktrees**:
  - Concurrent writers must use separate Git worktrees. Shared contracts, CMake configuration, and integration state have one writer at a time.
- **Commits**:
  - Format commit messages according to Conventional Commits: `type: short English summary`.
  - Use `tools/ai-commit` to register actual participants for managed commits.
