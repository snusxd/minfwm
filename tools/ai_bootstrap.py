#!/usr/bin/env python3
"""Activate only this checkout's reviewed workflow; no package installation."""

import argparse
from pathlib import Path
import subprocess
import sys


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--tool", required=True,
                        choices=("codex", "claude", "antigravity", "gemini"))
    args = parser.parse_args()
    root = Path(__file__).resolve().parent.parent
    commands = [
        ["tools/ai_profile.py", "validate"],
        ["tools/ai_workflow.py", "validate"],
        ["tools/ai_attribution.py", "install"],
        ["tools/ai_attribution.py", "session", "--tools", args.tool],
        ["tools/ai_attribution.py", "doctor"],
    ]
    for command in commands:
        result = subprocess.run([sys.executable, *command], cwd=root, check=False)
        if result.returncode:
            return result.returncode
    print("AI workflow active for this worktree; future sessions register their actual tool.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
