# Repository AI workflow

Repository policy is in `AGENTS.md`; the selected skill profile is
`.agents/workflow-stack.json`. New Codex work reads `AGENTS.md` and this page.
Open relevant skill guidance when an unfamiliar subsystem requires it.

For a routine change, use one worker only when isolation helps, provide the goal,
acceptance, owned paths, and one focused check, then inspect the result. Do not
create a task card or run a multi-role lifecycle by default. Use the seven-stage
runtime only for risky, multi-step, or parallel work. Concurrent code writers
use separate worktrees; shared contracts, CMake, instructions, and integration
state have one writer.

Register actual participants before managed commits and use
`tools/ai-commit --tools codex --task TASK-ID -- -m 'type: English summary'`.
Never invent identities or claim unavailable manual checks. Task cards and
workflow metadata remain in `docs/ai/tasks/` and `.agents/`; these machine-readable
files are not Wiki pages.
