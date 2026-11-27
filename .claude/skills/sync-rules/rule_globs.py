"""Shared `paths:` glob handling for the .claude/rules/ tooling.

Used by `check_rules.py` (glob liveness) and `codebase-map/rules_for.py`
(which rule files inject for a given source path). One home for the
brace-expansion and glob-to-regex rules, so both tools agree on what a
rule's `paths:` frontmatter matches.
"""

import pathlib
import re

RULES = pathlib.Path(".claude/rules")


def expand_braces(pattern):
    m = re.search(r"\{([^{}]*)\}", pattern)
    if not m:
        return [pattern]
    head, tail = pattern[: m.start()], pattern[m.end():]
    return [x for alt in m.group(1).split(",") for x in expand_braces(head + alt + tail)]


def glob_regex(pattern):
    out, i = "", 0
    while i < len(pattern):
        if pattern.startswith("**/", i):
            out, i = out + "(?:.*/)?", i + 3
        elif pattern.startswith("**", i):
            out, i = out + ".*", i + 2
        elif pattern[i] == "*":
            out, i = out + "[^/]*", i + 1
        elif pattern[i] == "?":
            out, i = out + "[^/]", i + 1
        else:
            out, i = out + re.escape(pattern[i]), i + 1
    return re.compile(f"^{out}$")


def frontmatter_paths(text):
    """The rule's `paths:` globs, or None for an always-on rule (no frontmatter)."""
    m = re.match(r"---\n(.*?)\n---\n", text, re.S)
    if not m:
        return None
    return [
        g.strip().strip("'\"")
        for g in re.findall(r"^\s*-\s*(.+?)\s*$", m.group(1), re.M)
    ]


def rule_matches(globs, path):
    return any(glob_regex(exp).match(path) for g in globs for exp in expand_braces(g))
