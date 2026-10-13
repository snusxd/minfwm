#!/usr/bin/env python3
"""Build the pinned Yabai SA extension locally; never installs or changes SIP."""
from pathlib import Path
import os
import shutil
import subprocess

ROOT = Path(__file__).resolve().parent.parent
SOURCE = ROOT / "build" / "yabai-minfwm"
COMMIT = "02de172f8706c3e2eaa679478897d7346e82b564"
PATCH = ROOT / "integrations" / "yabai" / "absolute-transform.patch"


def run(*args):
    subprocess.run(args, cwd=SOURCE, check=True)


def main():
    SOURCE.parent.mkdir(parents=True, exist_ok=True)
    if not SOURCE.exists():
        subprocess.run(["git", "clone", "--depth", "1", "--branch", "v7.1.25",
                        "https://github.com/asmvik/yabai.git", str(SOURCE)], check=True)
    actual = subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=SOURCE, text=True).strip()
    if actual != COMMIT:
        raise SystemExit("Unexpected Yabai checkout; refusing to patch it")
    applied = subprocess.run(["git", "apply", "--reverse", "--check", str(PATCH)],
                             cwd=SOURCE, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    if applied.returncode:
        run("git", "apply", "--check", str(PATCH))
        run("git", "apply", str(PATCH))
    shutil.copyfile(ROOT / "integrations/yabai/minfwm_transform.m", SOURCE / "src/osax/minfwm_transform.m")
    # Upstream's makefile does not list the extension include as a dependency.
    os.utime(SOURCE / "src/osax/payload.m", None)
    # Upstream generates two files in one rule; parallel make races on them.
    run("make", "-j1")
    print("Built:", SOURCE / "bin/yabai")
    print("Load from a terminal with sudo:", SOURCE / "bin/yabai", "--load-sa")


if __name__ == "__main__":
    main()
