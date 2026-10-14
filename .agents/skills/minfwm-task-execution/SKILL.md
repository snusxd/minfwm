---
name: minfwm-task-execution
description: Execute one ready minfwm task with fresh context, isolated ownership, focused checks, and a durable handoff.
---

# One task, one worker

This is a locally authored adapter. AgentFlow's coordinator owns dependencies,
stage changes and integration. Read `ADAPTATION.md` alongside this skill.

Accept one self-contained task packet: task/revision/attempt IDs, applicable
instructions, plan excerpt, acceptance, base SHA, dependencies, owned paths,
explicit non-goals, selected domain guidance, output artifact and checks.
Reject stale or contradictory packets to the coordinator before editing.

The coordinator dispatches a fresh worker for each independent ready task.
Prefer a bounded context without controller history when the host supports it;
otherwise record inherited context honestly. A worker does not dispatch another
orchestrator. Fixes within the same attempt may reuse this worker.

Before writing, verify the checkout/base and ownership. Use a separate worktree
and build directory for concurrent writers, reusing suitable host-managed
isolation. Never share an owned path with another live writer. Root instructions,
CMake and shared contracts need an exclusive writer or ordered dependency.
Preserve unrelated dirty files. Live macOS interaction has one explicit owner.

Add a focused CTest before changing a pure-core or wire contract. Perform the
smallest accepted change and required focused checks; maintain platform calls
at adapter boundaries. Register actual contribution participants before a commit
through the repository attribution tools. Do not guess identities or usage.

Return changed paths, result SHA and tree digest, command/exit/output evidence,
manual status with reason, contribution records, and unresolved gaps. If the
work is uncommitted, identify the dirty tree and never call it an accepted SHA.
Submit scope changes as proposals. Only the coordinator promotes stages or
accepts results; a late result for an old revision/attempt cannot be integrated.
