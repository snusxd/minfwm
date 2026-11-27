---
description: Commit the files you authored this session, staged by name, with a Conventional Commit message and no AI attribution
argument-hint: [optional hint about commit message focus]
---

Commit only the files you changed yourself in this conversation (Edit, Write, or a shell command that wrote a file). Leave everything else alone: pre-existing modifications, files the user or other agents changed, untracked files you didn't create.

1. Run `git status` and `git diff` in parallel.
2. List the files you touched this session; that exact set is what you stage. Empty set → say so and stop.
3. If the set touches `src/`, `tests/` or `CMakeLists.txt`, run the smallest affected check from `AGENTS.md` → "File-Scoped Commands" (full `ctest` at integration checkpoints). Docs/config-only commits skip this.
4. Message: `type: short English summary` (Conventional Commits, lowercase, imperative, no trailing period; follow `git log --oneline -10`). Body says why, if non-obvious. No `Co-Authored-By` or `AI-Tools` trailers: `.claude/settings.json` turns off Claude Code's trailer and `.githooks/commit-msg` strips a hand-typed Claude one.
5. `git add <file> ...` by name, never `-A` / `.`.
6. Run `git branch --show-current` and confirm the branch (parallel sessions share this tree), then plain `git commit` via HEREDOC. No `--no-verify` or `--amend`. Don't push: that is the owner's call.
7. List any dirty files outside your set under "**Not staged (not authored this session):**", then show `git show --stat HEAD`.

If `$ARGUMENTS` is given, treat it as a hint for the message, not a literal message.
