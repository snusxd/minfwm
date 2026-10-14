"""Integration tests use disposable repos/config only; run with unittest."""
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

SOURCE = Path(__file__).resolve().parents[1]


class AttributionTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.repo = Path(self.temporary.name) / 'repo'
        self.repo.mkdir()
        self.env = os.environ.copy()
        for key in list(self.env):
            if key.startswith('GIT_'):
                self.env.pop(key)
        self.env.update(GIT_CONFIG_NOSYSTEM='1', GIT_CONFIG_GLOBAL=os.devnull,
                        GIT_AUTHOR_NAME='Test Human', GIT_AUTHOR_EMAIL='human@example.test',
                        GIT_COMMITTER_NAME='Test Human', GIT_COMMITTER_EMAIL='human@example.test',
                        GIT_EDITOR='true')
        self.run_command('git', 'init', '-q')
        for name in ('tools/ai_attribution.py', 'tools/ai-commit', '.agents/ai-contributors.json',
                     '.githooks/prepare-commit-msg', '.githooks/commit-msg'):
            destination = self.repo / name
            destination.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(SOURCE / name, destination)
        self.stage('payload.txt', 'first\n')
        self.run_command('git', 'add', '.')
        self.run_command('git', 'commit', '-qm', 'chore: baseline')
        self.baseline = self.git('rev-parse', 'HEAD').strip()
        self.cli('install')
        self.cli('session', '--tools', 'codex', '--task', 'TASK-001')

    def tearDown(self):
        self.temporary.cleanup()

    def run_command(self, *arguments, ok=True, cwd=None, env=None):
        result = subprocess.run(arguments, cwd=cwd or self.repo, env=env or self.env,
                                stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        if ok:
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        else:
            self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)
        return result

    def git(self, *arguments, **kwargs):
        return self.run_command('git', *arguments, **kwargs).stdout

    def cli(self, *arguments, **kwargs):
        return self.run_command('python3', str(self.repo / 'tools/ai_attribution.py'), *arguments, **kwargs)

    def stage(self, name='payload.txt', text='second\n'):
        (self.repo / name).write_text(text)
        self.git('add', '--', name)

    def message(self):
        return self.git('log', '-1', '--format=%B')

    def test_direct_message_and_file_and_editor(self):
        for mode in ('message', 'file', 'editor'):
            self.stage(text=mode)
            if mode == 'message':
                self.git('commit', '-qm', 'docs: message\n\nBody text.\n\nCo-authored-by: Person <person@example.test>')
            elif mode == 'file':
                (self.repo / 'message').write_bytes(b'docs: file\r\n\r\nBody text.\r\n')
                self.git('commit', '-qF', 'message')
            else:
                editor = self.repo / 'editor.py'
                editor.write_text('#!/usr/bin/env python3\nimport pathlib,sys\np=pathlib.Path(sys.argv[1]);p.write_text("docs: editor\\n\\n"+p.read_text())\n')
                editor.chmod(0o755)
                env = dict(self.env, GIT_EDITOR=str(editor))
                self.git('commit', '-q', env=env)
            self.assertEqual(self.message().count('Co-authored-by: Codex <codex@ai.invalid>'), 1)
            self.assertIn('AI-Tools: codex', self.message())
        self.cli('check-history', '--baseline', self.baseline)

    def test_wrapper_record_and_partial_staging(self):
        self.stage(text='staged\n')
        (self.repo / 'payload.txt').write_text('unstaged\n')
        self.cli('commit', '--', '-m', 'feat: staged slice')
        message = self.message()
        self.assertIn('AI-Record:', message)
        self.assertEqual(self.git('show', 'HEAD:payload.txt'), 'staged\n')
        record_id = message.split('AI-Record: ')[1].splitlines()[0]
        record = json.loads(self.git('show', 'HEAD:.agents/contributions/' + record_id + '.json'))
        self.assertEqual(record['paths'], ['payload.txt'])
        self.assertEqual(record['tools'], ['codex'])
        self.cli('check-history', '--baseline', self.baseline)

    def test_amend_union_and_human_credits(self):
        self.stage()
        self.cli('commit', '--', '-m', 'feat: first\n\nCo-authored-by: Person <person@example.test>')
        self.cli('session', '--tools', 'claude')
        self.cli('commit', '--', '--amend', '--no-edit')
        message = self.message()
        self.assertIn('AI-Tools: claude, codex', message)
        self.assertEqual(message.count('Co-authored-by: Codex'), 1)
        self.assertIn('Co-authored-by: Person <person@example.test>', message)
        self.cli('session', '--tools', 'antigravity')
        self.cli('commit', '--', '--amend', '-m', 'feat: replaced message')
        self.assertIn('AI-Tools: antigravity, claude, codex', self.message())
        self.assertIn('Co-authored-by: Person <person@example.test>', self.message())
        self.cli('check-history', '--baseline', self.baseline)

    def test_human_none_and_invalid_tool(self):
        self.cli('session', '--human')
        self.stage()
        self.git('commit', '-qm', 'docs: human')
        self.assertIn('AI-Tools: none', self.message())
        self.assertNotIn('Co-authored-by:', self.message())
        for invalid in ('unknown', 'codex\nCo-authored-by: Evil <evil@example.test>', ''):
            self.cli('session', '--tools', invalid, ok=False)
        self.cli('check-history', '--baseline', self.baseline)

    def test_dedupe_existing_normalized_ai_and_preserve_human(self):
        self.stage()
        self.git('commit', '-qm', 'docs: canonical\n\nco-authored-by: codex <CODEX@AI.INVALID>\nCo-authored-by: Codex <codex@ai.invalid>\nCo-authored-by: Person <person@example.test>')
        self.assertEqual(self.message().count('Co-authored-by: Codex'), 1)
        self.assertIn('Co-authored-by: Person <person@example.test>', self.message())

    def test_no_verify_prepare_and_ci_bypass_detection(self):
        self.stage()
        self.git('commit', '--no-verify', '-qm', 'docs: no verify')
        self.assertIn('AI-Tools: codex', self.message())
        self.stage(text='bypass\n')
        self.git('-c', 'core.hooksPath=/dev/null', 'commit', '-qm', 'docs: bypass')
        result = self.cli('check-history', '--baseline', self.baseline, ok=False)
        self.assertIn('AI-Tools', result.stderr)

    def test_install_preserves_conflict_and_native_hooks(self):
        self.git('config', '--local', 'core.hooksPath', 'other-hooks')
        self.cli('install', ok=False)
        self.assertEqual(self.git('config', '--get', 'core.hooksPath').strip(), 'other-hooks')
        self.git('config', '--unset', 'core.hooksPath')
        hook = self.repo / '.git/hooks/pre-commit'
        hook.write_text('#!/bin/sh\nexit 0\n')
        hook.chmod(0o755)
        self.cli('install', ok=False)
        self.assertEqual(hook.read_text(), '#!/bin/sh\nexit 0\n')

    def test_linked_worktree_session_isolation(self):
        linked = Path(self.temporary.name) / 'linked'
        self.git('worktree', 'add', '-qb', 'other', str(linked))
        self.cli('session', '--tools', 'claude', cwd=linked)
        (linked / 'payload.txt').write_text('linked\n')
        self.git('add', 'payload.txt', cwd=linked)
        self.stage()
        processes = [subprocess.Popen(['git', 'commit', '-qm', 'docs: ' + label], cwd=checkout,
                                      env=self.env, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
                     for label, checkout in [('linked', linked), ('main', self.repo)]]
        for process in processes:
            stdout, stderr = process.communicate(timeout=30)
            self.assertEqual(process.returncode, 0, stdout + stderr)
        self.assertIn('AI-Tools: claude', self.git('log', '-1', '--format=%B', cwd=linked))
        self.assertIn('AI-Tools: codex', self.message())

    def test_missing_session_and_removed_credits_fail(self):
        self.cli('session', '--clear')
        self.stage()
        self.git('commit', '-qm', 'docs: no session', ok=False)
        self.cli('session', '--tools', 'codex')
        message = self.repo / 'bad-message'
        message.write_text('docs: edited\n\nAI-Tools: none\n')
        self.cli('commit-msg', str(message), ok=False)

    def test_wrapper_rejects_index_changing_and_bypass_options(self):
        self.stage()
        for argument in ('--no-verify', '-an', '--all', '--only', 'payload.txt', '--pathspec-from-file=x', '--dry-run'):
            self.cli('commit', '--', argument, '-m', 'docs: rejected', ok=False)
        self.assertEqual(self.git('rev-parse', 'HEAD').strip(), self.baseline)

    def test_freeze_changed_index_and_failed_attempt(self):
        hook = self.repo / '.githooks/pre-commit'
        hook.write_text('#!/bin/sh\nprintf changed > changed.txt\ngit add changed.txt\n')
        hook.chmod(0o755)
        self.stage()
        self.cli('commit', '--', '-m', 'feat: freeze', ok=False)
        self.assertEqual(self.git('rev-parse', 'HEAD').strip(), self.baseline)
        self.assertTrue((self.repo / '.git/minfwm-ai-pending.json').exists())
        self.cli('commit', '--', '-m', 'feat: retry', ok=False)
        self.cli('reset-pending')
        self.assertFalse((self.repo / '.git/minfwm-ai-pending.json').exists())

    def test_record_tamper_and_baseline_required(self):
        self.stage()
        self.cli('commit', '--', '-m', 'feat: record')
        record_id = self.message().split('AI-Record: ')[1].splitlines()[0]
        record_path = self.repo / '.agents/contributions' / (record_id + '.json')
        record = json.loads(record_path.read_text())
        record['tools'] = ['claude']
        record_path.write_text(json.dumps(record))
        self.git('add', str(record_path))
        self.git('-c', 'core.hooksPath=/dev/null', 'commit', '--amend', '--no-edit', '-q')
        self.cli('check-history', '--baseline', self.baseline, ok=False)
        self.cli('check-history', ok=False)
        self.cli('check-history', '--baseline', 'does-not-exist', ok=False)

    def test_doctor_active_probe_and_non_utf8(self):
        self.cli('doctor')
        message = self.repo / 'bad-message'
        message.write_bytes(b'docs: bad\xff\n')
        self.cli('check-message', str(message), ok=False)

    def test_symlink_record_directories_fail_before_external_writes(self):
        external = Path(self.temporary.name) / 'outside'
        external.mkdir()
        link = self.repo / '.agents/contributions'
        link.symlink_to(external, target_is_directory=True)
        self.stage()
        before = self.git('write-tree')
        self.cli('commit', '--', '-m', 'feat: must not escape', ok=False)
        self.assertEqual(list(external.iterdir()), [])
        self.assertEqual(self.git('write-tree'), before)
        self.assertEqual(self.git('rev-parse', 'HEAD').strip(), self.baseline)
        self.assertFalse((self.repo / '.git/minfwm-ai-pending.json').exists())
        # Even symlinks to another directory inside the checkout are refused.
        link.unlink()
        inside = self.repo / 'inside'
        inside.mkdir()
        link.symlink_to(inside, target_is_directory=True)
        self.cli('commit', '--', '-m', 'feat: must not follow', ok=False)
        self.assertEqual(list(inside.iterdir()), [])

    def test_symlink_registry_and_session_sidecars_are_rejected(self):
        external = Path(self.temporary.name) / 'external.json'
        external.write_text('sentinel')
        session = self.repo / '.git/minfwm-ai-session.json'
        session.unlink()
        session.symlink_to(external)
        self.cli('session', '--tools', 'claude', ok=False)
        self.assertEqual(external.read_text(), 'sentinel')
        self.assertTrue(session.is_symlink())
        session.unlink()
        self.cli('session', '--tools', 'codex')
        pending = self.repo / '.git/minfwm-ai-pending.json'
        pending.symlink_to(external)
        self.stage()
        self.cli('commit', '--tools', 'codex', '--', '-m', 'feat: reject pending link', ok=False)
        self.assertFalse((self.repo / '.agents/contributions').exists())
        self.assertEqual(external.read_text(), 'sentinel')
        pending.unlink()
        registry = self.repo / '.agents/ai-contributors.json'
        valid_registry = registry.read_text()
        external.write_text(valid_registry)
        registry.unlink()
        registry.symlink_to(external)
        self.cli('session', '--human', ok=False)
        self.assertEqual(external.read_text(), valid_registry)

    def test_local_squash_requires_source_and_preserves_union(self):
        self.git('checkout', '-qb', 'feature')
        self.stage(text='feature contribution\n')
        self.cli('commit', '--', '-m', 'feat: feature\n\nCo-authored-by: Person <person@example.test>')
        source = self.git('rev-parse', 'HEAD').strip()
        self.git('checkout', '-q', '-')
        self.cli('session', '--tools', 'claude')
        self.git('merge', '--squash', 'feature')
        staged = self.git('write-tree')
        records = sorted((self.repo / '.agents/contributions').glob('*.json'))
        result = self.cli('commit', '--', '-m', 'feat: squash', ok=False)
        self.assertIn('--squash-from', result.stderr)
        self.assertEqual(self.git('write-tree'), staged)
        self.assertEqual(sorted((self.repo / '.agents/contributions').glob('*.json')), records)
        self.assertFalse((self.repo / '.git/minfwm-ai-pending.json').exists())
        self.git('commit', '-qm', 'feat: direct squash rejected', ok=False)
        self.cli('commit', '--squash-from', 'feature', '--', '-m', 'feat: squash')
        self.assertIn('AI-Tools: claude, codex', self.message())
        self.assertIn('Co-authored-by: Person <person@example.test>', self.message())
        record_id = self.message().split('AI-Record: ')[1].splitlines()[0]
        record = json.loads(self.git('show', 'HEAD:.agents/contributions/' + record_id + '.json'))
        self.assertEqual(record['sources'], [source])
        self.cli('check-history', '--baseline', self.baseline)
        self.cli('commit', '--squash-from', 'feature', '--', '-m', 'feat: no pending squash', ok=False)

    def test_relative_candidate_and_trusted_policy_roots(self):
        parent = Path(self.temporary.name)
        trusted = parent / 'trusted'
        trusted.mkdir()
        shutil.copytree(self.repo / '.agents', trusted / '.agents')
        self.stage()
        self.git('commit', '-qm', 'docs: candidate')
        # The roots are siblings relative to the caller, not to the candidate.
        self.run_command('python3', str(SOURCE / 'tools/ai_attribution.py'),
                         '--repo', 'repo', '--policy-root', 'trusted', 'check-history',
                         '--baseline', self.baseline, cwd=parent)

    def test_crash_reconciliation_does_not_commit_twice(self):
        self.stage()
        self.cli('commit', '--', '-m', 'feat: committed before crash')
        head = self.git('rev-parse', 'HEAD').strip()
        record_id = self.message().split('AI-Record: ')[1].splitlines()[0]
        pending = {'record_id': record_id, 'tools': ['codex'], 'base': self.baseline,
                   'tree': self.git('rev-parse', 'HEAD^{tree}').strip()}
        (self.repo / '.git/minfwm-ai-pending.json').write_text(json.dumps(pending))
        result = self.cli('commit', '--', '-m', 'feat: must not create second commit')
        self.assertIn('Reconciled existing', result.stdout)
        self.assertEqual(self.git('rev-parse', 'HEAD').strip(), head)
        self.assertFalse((self.repo / '.git/minfwm-ai-pending.json').exists())

    def test_trusted_script_and_registry_against_candidate(self):
        self.stage()
        self.git('commit', '-qm', 'docs: candidate')
        (self.repo / 'tools/ai_attribution.py').write_text('raise RuntimeError("untrusted code executed")')
        (self.repo / '.agents/ai-contributors.json').write_text('{}')
        self.run_command('python3', str(SOURCE / 'tools/ai_attribution.py'), '--repo', str(self.repo),
                         '--policy-root', str(SOURCE), 'check-history', '--baseline', self.baseline)

    def test_direct_revert_credits_current_session(self):
        self.stage()
        self.git('commit', '-qm', 'feat: original')
        self.cli('session', '--tools', 'claude')
        self.git('revert', '--no-edit', 'HEAD')
        self.assertIn('AI-Tools: claude', self.message())
        self.assertNotIn('Co-authored-by: Codex', self.message())
        self.cli('check-history', '--baseline', self.baseline)

    def test_reused_message_union(self):
        self.stage()
        self.cli('commit', '--', '-m', 'feat: original')
        reference = self.git('rev-parse', 'HEAD').strip()
        self.cli('session', '--tools', 'claude')
        self.stage(text='another\n')
        self.cli('commit', '--', '-C', reference)
        self.assertIn('AI-Tools: claude, codex', self.message())
        self.cli('check-history', '--baseline', self.baseline)


if __name__ == '__main__':
    unittest.main()
