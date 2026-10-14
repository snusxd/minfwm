#!/usr/bin/env python3
"""Read-only selected skill profile checks; never installs or calls a backend."""

import argparse
import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import re
import sys


MANIFEST = ".agents/workflow-stack.json"
PROCESS = {"agentflow", "plan-writing", "agents-md", "research-prompt", "deep-research"}
ADAPTERS = {"minfwm-task-execution", "minfwm-review", "minfwm-verification"}
ROUTING = {
    "coordinator": ["agentflow"], "instructions": ["agents-md"],
    "research_planner": ["research-prompt"], "researcher": ["deep-research"],
    "planner": ["plan-writing"], "builder": ["minfwm-task-execution"],
    "reviewer": ["minfwm-review"], "verifier": ["minfwm-verification"],
    "integrator": ["minfwm-verification"],
}
STAGES = ["backlog", "research", "build", "review", "test", "integrate", "done"]


class ProfileError(ValueError):
    pass


def local_path(root, value):
    """Reject lexical traversal and symlink escapes before opening any file."""
    if not isinstance(value, str) or not value or "\\" in value:
        raise ProfileError("invalid repository-relative path")
    path = PurePosixPath(value)
    if path.is_absolute() or ".." in path.parts or re.match(r"^[A-Za-z]:", value):
        raise ProfileError("path must stay inside the repository")
    result = root.joinpath(*path.parts).resolve()
    if not result.is_relative_to(root.resolve()):
        raise ProfileError("path escapes repository through symlink")
    return result


def check_file(root, entry):
    path = local_path(root, entry["path"])
    if not path.is_file():
        raise ProfileError("missing profile file: " + entry["path"])
    expected = entry.get("sha256", "")
    if not isinstance(expected, str) or not re.fullmatch(r"[0-9a-f]{64}", expected):
        raise ProfileError("invalid SHA-256: " + entry["path"])
    if hashlib.sha256(path.read_bytes()).hexdigest() != expected:
        raise ProfileError("stale SHA-256: " + entry["path"])


def load_profile(root):
    try:
        profile = json.loads(local_path(root, MANIFEST).read_text())
        validate_profile(root, profile)
        return profile
    except (OSError, ValueError, KeyError, TypeError, AttributeError) as error:
        raise ProfileError(str(error)) from error


def validate_profile(root, profile):
    if profile["schema_version"] != 1 or profile["canonical_stages"] != STAGES:
        raise ProfileError("unknown schema version or canonical stages")
    if len(profile["process_skills"]) != 5 or set(profile["process_skills"]) != PROCESS:
        raise ProfileError("profile must select the exact five process skills")
    entries = profile["skills"]
    if len(entries) != 8 or {item["id"] for item in entries} != PROCESS | ADAPTERS:
        raise ProfileError("profile must contain exactly eight selected skills")
    if profile["role_skills"] != ROUTING:
        raise ProfileError("unknown role or altered stage routing")
    for entry in entries:
        name = entry["id"]
        if entry["path"] != f".agents/skills/{name}/SKILL.md":
            raise ProfileError("unexpected skill path: " + name)
        expected_roles = {role for role, ids in ROUTING.items() if name in ids}
        if set(entry["roles"]) != expected_roles:
            raise ProfileError("unknown role or wrong skill roles: " + name)
        check_file(root, entry)
        if entry["source_sha256"] != entry["sha256"]:
            raise ProfileError("source hash differs from exact supplied/authored bytes: " + name)
        if entry["source"]["kind"] not in {"user-provided-local", "locally-authored"}:
            raise ProfileError("unknown source kind: " + name)
        if not entry["license"]["status"]:
            raise ProfileError("missing license provenance: " + name)
        check_file(root, entry["adaptation"])
        for helper in entry["helpers"]:
            path = local_path(root, helper["path"])
            if type(helper["required"]) is not bool:
                raise ProfileError("helper required flag must be boolean")
            if helper["required"]:
                check_file(root, helper)
            elif helper.get("status") != "not-supplied-runtime-unavailable":
                raise ProfileError("optional helper must explain unavailable runtime")
            elif path.exists():
                raise ProfileError("unreviewed optional helper appeared: " + helper["path"])
    inventory = json.loads(local_path(root, profile["historical_inventory"]).read_text())
    old = profile["existing_skills"]
    if len(old) != 15 or {entry["id"] for entry in old} != {item["id"] for item in inventory["skills"]}:
        raise ProfileError("existing skill dispositions must cover the historical fifteen")
    counts = {"active-domain": 0, "conditional": 0, "excluded": 0}
    for entry in old:
        if entry["disposition"] not in counts:
            raise ProfileError("unknown existing skill disposition")
        counts[entry["disposition"]] += 1
        if not entry["trigger"] or not set(entry["roles"]).issubset(ROUTING):
            raise ProfileError("missing trigger or unknown domain role")
        if entry["path"] != f".agents/skills/{entry['id']}/SKILL.md":
            raise ProfileError("unexpected domain skill path")
        check_file(root, entry)
    if counts != {"active-domain": 2, "conditional": 9, "excluded": 4}:
        raise ProfileError("expected two active, nine conditional, four excluded domains")
    backend = profile["deep_research"]
    if (backend["runner"] != ".agents/skills/deep-research/scripts/research.py"
            or backend["key_environment"] != "GEMINI_API_KEY"
            or backend["backend_reviewed"] is not False
            or backend["fallback"] != "web-subagent"):
        raise ProfileError("backend must remain explicitly unavailable until separately reviewed")
    local_path(root, backend["runner"])


def doctor(root, profile):
    backend = profile["deep_research"]
    runner = local_path(root, backend["runner"]).is_file()
    key = bool(os.environ.get(backend["key_environment"]))
    return {
        "profile": "valid", "local_git_adapter": "available" if (root / "tools/ai_workflow.py").is_file() else "unavailable",
        "gemini_deep_research": {"status": "unavailable", "runner_present": runner,
                                 "key_present": key, "backend_reviewed": False,
                                 "reason": "runner not supplied; backend not reviewed",
                                 "fallback": backend["fallback"]},
        "paid_calls_attempted": False,
    }


def task_packet(root, profile, role, domains):
    selected = [entry for entry in profile["skills"] if entry["id"] in ROUTING[role]]
    for name in domains:
        matches = [entry for entry in profile["existing_skills"] if entry["id"] == name]
        if not matches or matches[0]["disposition"] == "excluded" or role not in matches[0]["roles"]:
            raise ProfileError("domain unavailable for selected role: " + name)
        if matches[0] not in selected:
            selected.append(matches[0])
    skills = []
    for entry in selected:
        item = {"id": entry["id"], "path": entry["path"], "sha256": entry["sha256"],
                "content": local_path(root, entry["path"]).read_text()}
        if "adaptation" in entry:
            item["execution_contract"] = local_path(root, entry["adaptation"]["path"]).read_text()
        skills.append(item)
    return {"schema_version": 1, "role": role, "skills": skills,
            "backend": doctor(root, profile)["gemini_deep_research"] if role == "researcher" else None,
            "note": "Skill context only; coordinator must attach task acceptance, instructions, ownership and SHA."}


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, default=Path(__file__).resolve().parents[1])
    commands = parser.add_subparsers(dest="command", required=True)
    commands.add_parser("validate")
    commands.add_parser("doctor")
    packet = commands.add_parser("packet")
    packet.add_argument("--role", required=True, choices=ROUTING)
    packet.add_argument("--domain", action="append", default=[])
    args = parser.parse_args(argv)
    try:
        root = args.root.resolve()
        profile = load_profile(root)
        if args.command == "validate":
            result = {"profile": "valid", "selected_skills": 8, "process_skills": 5}
        elif args.command == "doctor":
            result = doctor(root, profile)
        else:
            result = task_packet(root, profile, args.role, args.domain)
        print(json.dumps(result, indent=2))
        return 0
    except ProfileError as error:
        print("ai_profile: " + str(error), file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
