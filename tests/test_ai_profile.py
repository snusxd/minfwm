"""Profile integrity and bounded-context checks using disposable copies."""

import contextlib
import importlib.util
import io
import json
import os
from pathlib import Path
import shutil
import tempfile
import unittest
from unittest.mock import patch


ROOT = Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location("ai_profile", ROOT / "tools/ai_profile.py")
profile = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(profile)


class ProfileTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.root = Path(self.directory.name)
        shutil.copytree(ROOT / ".agents/skills", self.root / ".agents/skills")
        shutil.copyfile(ROOT / profile.MANIFEST, self.root / profile.MANIFEST)
        (self.root / "docs/ai").mkdir(parents=True)
        shutil.copyfile(ROOT / "docs/ai/aas-stack.json", self.root / "docs/ai/aas-stack.json")

    def change_manifest(self, mutate):
        path = self.root / profile.MANIFEST
        data = json.loads(path.read_text())
        mutate(data)
        path.write_text(json.dumps(data))

    def test_clean_profile_selects_only_five_process_skills(self):
        data = profile.load_profile(self.root)
        self.assertEqual(set(data["process_skills"]), profile.PROCESS)
        self.assertEqual(len(data["skills"]), 8)

    def test_modified_skill_is_rejected(self):
        with (self.root / ".agents/skills/agentflow/SKILL.md").open("a") as output:
            output.write("\nchanged bytes\n")
        with self.assertRaisesRegex(profile.ProfileError, "stale SHA-256"):
            profile.load_profile(self.root)

    def test_missing_skill_is_rejected(self):
        (self.root / ".agents/skills/plan-writing/SKILL.md").unlink()
        with self.assertRaisesRegex(profile.ProfileError, "missing profile file"):
            profile.load_profile(self.root)

    def test_missing_required_helper_is_rejected(self):
        self.change_manifest(lambda data: data["skills"][0]["helpers"].append({
            "path": ".agents/skills/agentflow/helper.md", "required": True,
            "sha256": "0" * 64,
        }))
        with self.assertRaisesRegex(profile.ProfileError, "missing profile file"):
            profile.load_profile(self.root)

    def test_unavailable_runtime_does_not_claim_helper_closure(self):
        data = profile.load_profile(self.root)
        research = next(item for item in data["skills"] if item["id"] == "deep-research")
        self.assertEqual(len(research["helpers"]), 2)
        self.assertTrue(all(not item["required"] for item in research["helpers"]))
        runner = self.root / data["deep_research"]["runner"]
        runner.parent.mkdir()
        runner.write_text("# unreviewed\n")
        with self.assertRaisesRegex(profile.ProfileError, "unreviewed optional helper"):
            profile.load_profile(self.root)

    def test_lexical_path_traversal_is_rejected(self):
        for value in ("../escape", "/tmp/escape", "a/../../escape", "C:/escape", "a\\escape"):
            with self.subTest(value=value), self.assertRaises(profile.ProfileError):
                profile.local_path(self.root, value)
        self.change_manifest(lambda data: data["skills"][0]["adaptation"].update(path="../escape"))
        with self.assertRaisesRegex(profile.ProfileError, "inside the repository"):
            profile.load_profile(self.root)

    def test_symlink_escape_is_rejected(self):
        target = self.root / ".agents/skills/agentflow/ADAPTATION.md"
        target.unlink()
        target.symlink_to(ROOT / "README.md")
        with self.assertRaisesRegex(profile.ProfileError, "symlink"):
            profile.load_profile(self.root)

    def test_unknown_role_is_rejected(self):
        self.change_manifest(lambda data: data["role_skills"].update(rogue=["agentflow"]))
        with self.assertRaisesRegex(profile.ProfileError, "unknown role"):
            profile.load_profile(self.root)

    def test_domain_routing_is_explicit_and_excluded_skills_unavailable(self):
        data = profile.load_profile(self.root)
        packet = profile.task_packet(self.root, data, "builder", ["cpp-pro"])
        self.assertEqual([item["id"] for item in packet["skills"]], ["minfwm-task-execution", "cpp-pro"])
        for excluded in ("ai-native-cli", "api-security-best-practices", "orchestrate-batch-refactor", "acceptance-orchestrator"):
            with self.subTest(excluded=excluded), self.assertRaises(profile.ProfileError):
                profile.task_packet(self.root, data, "builder", [excluded])

    def test_stage_packet_contains_no_other_process_context(self):
        data = profile.load_profile(self.root)
        for role, ids in profile.ROUTING.items():
            with self.subTest(role=role):
                packet = profile.task_packet(self.root, data, role, [])
                self.assertEqual([item["id"] for item in packet["skills"]], ids)
                self.assertTrue(all(item["content"] for item in packet["skills"]))

    def test_doctor_never_reports_secret_or_available_backend(self):
        data = profile.load_profile(self.root)
        secret = "must-never-appear-in-output"
        for key in ("", secret):
            with self.subTest(key_present=bool(key)), patch.dict(os.environ, {"GEMINI_API_KEY": key}):
                result = profile.doctor(self.root, data)
                self.assertEqual(result["gemini_deep_research"]["status"], "unavailable")
                self.assertEqual(result["gemini_deep_research"]["key_present"], bool(key))
                self.assertFalse(result["paid_calls_attempted"])
                self.assertNotIn(secret, json.dumps(result))

    def test_cli_invalid_profile_exits_nonzero(self):
        self.change_manifest(lambda data: data.update(schema_version=99))
        with contextlib.redirect_stderr(io.StringIO()):
            self.assertEqual(profile.main(["--root", str(self.root), "validate"]), 1)


if __name__ == "__main__":
    unittest.main()
