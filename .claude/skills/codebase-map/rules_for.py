#!/usr/bin/env python3
"""List the .claude/rules/ files that apply to the given source paths.

Run from the repo root:

    python3 .claude/skills/codebase-map/rules_for.py src/daemon/WindowManager.mm src/core/Camera.cpp

Claude Code injects a path-scoped rule on the first read of a matching file;
agents without that hook (Codex, Cursor, Gemini, or a Claude session after
/compact) run this and read the files it prints before editing. Always-on
rules (no `paths:` frontmatter) are listed once at the top.
"""

import pathlib
import sys

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent.parent / "sync-rules"))

from rule_globs import RULES, frontmatter_paths, rule_matches  # noqa: E402

if len(sys.argv) < 2:
    sys.exit(__doc__.strip())

rules = [(r, frontmatter_paths(r.read_text())) for r in sorted(RULES.rglob("*.md"))]
print("always:", " ".join(["CLAUDE.md"] + [str(r) for r, g in rules if g is None]))
for path in sys.argv[1:]:
    path = path.removeprefix("./")
    hits = [str(r) for r, g in rules if g is not None and rule_matches(g, path)]
    print(f"{path}: {' '.join(hits) if hits else '(no path-scoped rule)'}")
