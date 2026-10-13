#!/usr/bin/env python3
"""Build the pinned Yabai SA extension locally; never installs or changes SIP."""
from pathlib import Path
import os
import shutil
import subprocess
import tempfile

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
        check = subprocess.run(["git", "apply", "--check", str(PATCH)], cwd=SOURCE,
                               stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        if check.returncode:
            # Upgrade only the exact previous generated patch, never an unknown
            # dirty checkout. Its payload is not installed by this script.
            current = PATCH.read_text()
            previous_overview = current.replace("0x780; // minfwm translation, lifecycle, overview and native handoff",
                                                "0x380; // minfwm translation, lifecycle and overview scale").replace(
                "com.minfwm.yabai-sa.overview2", "com.minfwm.yabai-sa.overview1")
            previous_v2 = previous_overview.replace("0x380; // minfwm translation, lifecycle and overview scale",
                                          "0x180; // minfwm absolute translation + reset extension").replace(
                "com.minfwm.yabai-sa.overview1", "com.minfwm.yabai-sa.lifecycle2")
            previous_v1 = previous_v2.replace("0x180", "0x80").replace(
                "com.minfwm.yabai-sa.lifecycle2", "com.minfwm.yabai-sa")
            for previous in (previous_overview, previous_v2, previous_v1):
                with tempfile.NamedTemporaryFile(mode="w", suffix=".patch") as old:
                    old.write(previous)
                    old.flush()
                    check = subprocess.run(["git", "apply", "--reverse", "--check", old.name],
                                           cwd=SOURCE, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
                    if check.returncode == 0:
                        run("git", "apply", "--reverse", old.name)
                        break
            else:
                raise SystemExit("Unknown Yabai modifications; refusing to overwrite them")
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
