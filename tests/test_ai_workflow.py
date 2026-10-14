"""Behavioral tests run in disposable Git repositories; no macOS permissions needed."""
import contextlib
import importlib.util
import io
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

MODULE_PATH = Path(__file__).resolve().parents[1] / 'tools' / 'ai_workflow.py'
spec = importlib.util.spec_from_file_location('ai_workflow', MODULE_PATH)
workflow = importlib.util.module_from_spec(spec)
spec.loader.exec_module(workflow)


class WorkflowTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.repo = Path(self.temp.name)
        self.git('init', '-q')
        self.git('config', 'user.name', 'Workflow fixture')
        self.git('config', 'user.email', 'fixture@example.invalid')
        (self.repo / 'plan.md').write_text('Frozen task plan\n')
        (self.repo / 'source.txt').write_text('baseline\n')
        (self.repo / '.gitignore').write_text('build/\n')
        self.git('add', '.')
        self.git('commit', '-qm', 'test: fixture baseline')
        self.rt = workflow.Runtime(self.repo)
        self.create()

    def tearDown(self):
        self.temp.cleanup()

    def git(self, *args):
        return subprocess.check_output(['git', '-C', str(self.repo), *args], text=True).strip()

    def cli(self, *args, ok=True):
        out, err = io.StringIO(), io.StringIO()
        with contextlib.redirect_stdout(out), contextlib.redirect_stderr(err):
            code = workflow.main(['--repo', str(self.repo), *args])
        if ok:
            self.assertEqual(code, 0, err.getvalue())
            return json.loads(out.getvalue())
        self.assertNotEqual(code, 0, out.getvalue())
        return err.getvalue()

    def create(self, task='TASK-one', owned='edit:source.txt', deps=()):
        args = ['create', task, '--title', 'Fixture task', '--plan', 'plan.md', '--summary', 'One bounded outcome',
                '--acceptance', 'Actual command evidence passes', '--owned', owned, '--read', 'plan.md',
                '--manual-reason', 'No live window behavior', '--coordinator', 'coordinator']
        for dep in deps:
            args += ['--dependency', dep]
        return self.cli(*args)

    def mutate(self, task='TASK-one', **updates):
        value = self.rt.task(task)
        value.update(updates)
        workflow.atomic_json(self.rt.cards / (task + '.json'), value)
        return value

    def stage(self, target, reason=None):
        args = ['transition', 'TASK-one', target, '--coordinator', 'coordinator']
        if reason:
            args += ['--reason', reason]
        return self.cli(*args)

    def build_claim(self):
        self.stage('research')
        self.stage('build', 'Research not needed for fixture')
        return self.claim('worker', 'worker-1')

    def claim(self, role, agent):
        return self.cli('claim', 'TASK-one', '--role', role, '--agent', agent, '--coordinator', 'coordinator')

    def release(self, lease):
        self.cli('release', 'TASK-one', '--token', lease['token'], '--coordinator', 'coordinator')

    def proof(self, lease, kind='focused', command=None, ok=True):
        return self.cli('evidence', 'TASK-one', '--token', lease['token'], '--kind', kind, '--',
                        *(command or [sys.executable, '-c', 'print("verified")']), ok=ok)

    def reviewed_test(self, dirty=False):
        worker = self.build_claim()
        if dirty:
            (self.repo / 'source.txt').write_text('uncommitted accepted candidate\n')
        self.proof(worker)
        self.release(worker)
        self.stage('review')
        reviewer = self.claim('reviewer', 'reviewer-1')
        self.cli('review', 'TASK-one', '--token', reviewer['token'], '--spec', 'pass', '--quality', 'pass', '--summary', 'Independent checks passed')
        self.release(reviewer)
        self.stage('test')
        return self.claim('tester', 'tester-1')

    def test_full_lifecycle_and_packet(self):
        packet = self.cli('packet', 'TASK-one', '--role', 'worker')
        self.assertNotIn('history', packet)
        tester = self.reviewed_test()
        self.proof(tester, 'full')
        self.release(tester)
        self.stage('integrate')
        result = self.cli('finish', 'TASK-one', '--summary', 'Accepted fixture', '--coordinator', 'coordinator')
        self.assertEqual(result['stage'], 'done')
        self.assertEqual(result['accepted_sha'], self.rt.head())
        self.assertEqual(result['usage'], 'unavailable')
        self.git('commit', '--allow-empty', '-qm', 'test: later unrelated history')
        self.cli('validate')

    def test_unknown_dependency_and_cycle(self):
        self.mutate(dependencies=['TASK-missing'])
        self.assertIn('unknown dependency', self.cli('validate', ok=False))
        self.mutate(dependencies=[])
        self.create('TASK-two', 'create:new.txt', deps=['TASK-one'])
        self.mutate(dependencies=['TASK-two'])
        self.assertIn('cycle', self.cli('validate', ok=False))

    def test_all_dependencies_and_active_prefix_overlap(self):
        self.create('TASK-two', 'create:new.txt', deps=['TASK-one'])
        self.mutate('TASK-two', stage='build')
        self.assertIn('dependencies', self.cli('claim', 'TASK-two', '--role', 'worker', '--agent', 'w2', '--coordinator', 'coordinator', ok=False))
        self.mutate('TASK-two', dependencies=[], owned_paths=[{'path': 'source.txt', 'operation': 'edit'}])
        self.build_claim()
        self.assertIn('conflict', self.cli('claim', 'TASK-two', '--role', 'worker', '--agent', 'w2', '--coordinator', 'coordinator', ok=False))
        self.assertTrue(workflow.overlaps('src/core', 'src/core/File.cpp'))
        self.assertFalse(workflow.overlaps('src/core', 'src/core2'))

    def test_expiry_recovery_and_late_duplicate_results(self):
        old = self.build_claim()
        path = self.rt.lease_path('TASK-one')
        lease = workflow.read_json(path)
        lease['expires'] = 0
        workflow.atomic_json(path, lease)
        self.assertIn('expired', self.proof(old, ok=False))
        self.cli('recover', '--coordinator', 'coordinator')
        new = self.claim('worker', 'worker-2')
        self.assertGreater(new['attempt'], old['attempt'])
        self.assertIn('stale fencing', self.proof(old, ok=False))
        self.proof(new)
        self.release(new)
        self.assertIn('no active claim', self.proof(new, ok=False))

    def test_orphan_recovery_and_frozen_spec(self):
        worker = self.build_claim()
        self.proof(worker)
        task = self.rt.task('TASK-one')
        task['spec']['acceptance'].append('Changed after verification')
        self.mutate(spec=task['spec'])
        self.assertIn('scope changed', self.proof(worker, ok=False))
        self.cli('recover', '--coordinator', 'coordinator')
        self.assertIn('evidence', self.cli('transition', 'TASK-one', 'review', '--coordinator', 'coordinator', ok=False))
        new = self.claim('worker', 'worker-2')
        self.rt.lease_path('TASK-one').unlink()
        self.assertIn('orphaned', self.cli('claim', 'TASK-one', '--role', 'worker', '--agent', 'worker-3', '--coordinator', 'coordinator', ok=False))
        recovered = self.cli('recover', '--coordinator', 'coordinator')
        self.assertEqual(recovered['recovered'], ['TASK-one'])
        self.assertGreater(self.rt.task('TASK-one')['execution']['attempt'], new['attempt'])

    def test_done_card_requires_actual_accepted_proofs(self):
        self.mutate(stage='done', accepted_sha=self.rt.head(), accepted_digest=self.rt.digest())
        self.assertIn('full evidence missing', self.cli('validate', ok=False))

    def test_worker_cannot_review_self(self):
        worker = self.build_claim()
        self.proof(worker)
        self.release(worker)
        self.stage('review')
        self.assertIn('cannot review', self.cli('claim', 'TASK-one', '--role', 'reviewer', '--agent', 'worker-1', '--coordinator', 'coordinator', ok=False))

    def test_pending_manual_blocks_integrate_then_fresh_manual_passes(self):
        tester = self.reviewed_test()
        self.mutate(manual={'status': 'pending', 'reason': 'Visible behavior requires human check'})
        self.proof(tester, 'full')
        self.release(tester)
        self.assertIn('manual', self.cli('transition', 'TASK-one', 'integrate', '--coordinator', 'coordinator', ok=False))
        tester = self.claim('tester', 'tester-2')
        self.cli('evidence', 'TASK-one', '--token', tester['token'], '--kind', 'manual', '--status', 'passed', '--note', 'Recorded actual human acceptance')
        self.release(tester)
        self.stage('integrate')
        self.cli('finish', 'TASK-one', '--summary', 'Accepted', '--coordinator', 'coordinator')

    def test_head_change_invalidates_evidence_even_equal_tree(self):
        worker = self.build_claim()
        self.proof(worker)
        self.release(worker)
        self.git('commit', '--allow-empty', '-qm', 'test: changed commit identity')
        self.assertIn('actual SHA', self.cli('transition', 'TASK-one', 'review', '--coordinator', 'coordinator', ok=False))

    def test_dirty_content_and_evidence_command_mutation(self):
        worker = self.build_claim()
        self.proof(worker)
        (self.repo / 'source.txt').write_text('changed\n')
        self.release(worker)
        self.assertIn('current digest', self.cli('transition', 'TASK-one', 'review', '--coordinator', 'coordinator', ok=False))
        worker = self.claim('worker', 'worker-2')
        self.assertIn('changed the checked tree', self.proof(worker, command=[sys.executable, '-c', 'open("source.txt", "w").write("mutated")'], ok=False))

    def test_failed_command_records_failure_and_no_shell_eval(self):
        worker = self.build_claim()
        self.proof(worker, command=[sys.executable, '-c', 'raise SystemExit(3)'], ok=False)
        task = self.rt.task('TASK-one')
        self.assertEqual(task['evidence'][-1]['exit_code'], 3)
        self.proof(worker, command=[sys.executable, '-c', 'import sys; print(sys.argv[1])', '$(touch injected)'])
        self.assertFalse((self.repo / 'injected').exists())

    def test_path_operations_and_read_set(self):
        self.create('TASK-created', 'create:new.txt')
        self.create('TASK-deleted', 'delete:source.txt')
        self.mutate(read_set=['../secret'])
        self.assertIn('unsafe', self.cli('validate', ok=False))
        self.mutate(read_set=['missing.txt'])
        self.assertIn('absent at base', self.cli('validate', ok=False))
        self.mutate(read_set=['plan.md'], owned_paths=[{'path': 'source.txt', 'operation': 'create'}])
        self.assertIn('conflicts with base', self.cli('validate', ok=False))

    def test_dirty_finish_and_worktree_candidate(self):
        checkout = self.repo / 'build' / 'worker'
        checkout.parent.mkdir()
        self.git('worktree', 'add', '--detach', str(checkout), 'HEAD')
        rt = workflow.Runtime(self.repo, checkout)
        self.assertEqual(rt.repo, self.repo.resolve())
        self.assertEqual(rt.checkout, checkout.resolve())
        self.assertEqual(rt.digest(), rt.committed_digest(rt.head()))
        (checkout / 'source.txt').write_text('candidate change\n')
        self.assertNotEqual(rt.digest(), self.rt.digest())
        with self.assertRaisesRegex(workflow.WorkflowError, 'commit candidate'):
            rt.require_clean_candidate()
        other = Path(self.temp.name) / 'foreign'
        other.mkdir()
        subprocess.run(['git', 'init', '-q', str(other)], check=True)
        with self.assertRaisesRegex(workflow.WorkflowError, 'not a linked worktree'):
            workflow.Runtime(self.repo, other)

    def test_linked_worktree_lifecycle_keeps_one_canonical_ledger(self):
        checkout = self.repo / 'build' / 'candidate'
        checkout.parent.mkdir()
        self.git('worktree', 'add', '--detach', str(checkout), 'HEAD')
        def candidate(*args):
            return self.cli('--checkout', str(checkout), *args)
        self.stage('research')
        self.stage('build', 'No research needed')
        worker = candidate('claim', 'TASK-one', '--role', 'worker', '--agent', 'worktree-worker', '--coordinator', 'coordinator')
        (checkout / 'source.txt').write_text('actual candidate\n')
        subprocess.run(['git', '-C', str(checkout), 'add', 'source.txt'], check=True)
        subprocess.run(['git', '-C', str(checkout), 'commit', '-qm', 'test: candidate source'], check=True)
        proof = candidate('evidence', 'TASK-one', '--token', worker['token'], '--kind', 'focused', '--', sys.executable, '-c', 'print(open("source.txt").read())')
        self.assertIn('actual candidate', proof['output_tail'])
        self.assertNotEqual(proof['binding']['sha'], self.rt.head())
        self.release(worker)
        candidate('transition', 'TASK-one', 'review', '--coordinator', 'coordinator')
        reviewer = candidate('claim', 'TASK-one', '--role', 'reviewer', '--agent', 'worktree-reviewer', '--coordinator', 'coordinator')
        candidate('review', 'TASK-one', '--token', reviewer['token'], '--spec', 'pass', '--quality', 'pass', '--summary', 'Actual candidate reviewed')
        self.release(reviewer)
        candidate('transition', 'TASK-one', 'test', '--coordinator', 'coordinator')
        tester = candidate('claim', 'TASK-one', '--role', 'tester', '--agent', 'worktree-tester', '--coordinator', 'coordinator')
        candidate('evidence', 'TASK-one', '--token', tester['token'], '--kind', 'full', '--', sys.executable, '-c', 'print("full candidate checks")')
        self.release(tester)
        candidate('transition', 'TASK-one', 'integrate', '--coordinator', 'coordinator')
        done = candidate('finish', 'TASK-one', '--summary', 'Candidate accepted', '--coordinator', 'coordinator')
        self.assertEqual(done['accepted_sha'], proof['binding']['sha'])
        self.assertEqual((self.repo / 'source.txt').read_text(), 'baseline\n')
        self.assertFalse((checkout / workflow.CARDS).exists())
        self.cli('validate')

    def test_finish_rejects_tested_but_uncommitted_candidate(self):
        tester = self.reviewed_test(dirty=True)
        self.proof(tester, 'full')
        self.release(tester)
        self.stage('integrate')
        self.assertIn('commit candidate', self.cli('finish', 'TASK-one', '--summary', 'Must not accept dirty result', '--coordinator', 'coordinator', ok=False))

    def test_worker_cannot_certify_outside_scope_changes(self):
        worker = self.build_claim()
        (self.repo / 'plan.md').write_text('out of scope change\n')
        self.assertIn('outside owned paths', self.proof(worker, ok=False))

    def test_coordinator_and_atomic_mutation_lock(self):
        self.assertIn('owned by', self.cli('recover', '--coordinator', 'another', ok=False))
        with self.rt.locked('coordinator'):
            self.assertIn('in progress', self.cli('recover', '--coordinator', 'coordinator', ok=False))

    def test_packet_budget_and_real_base(self):
        self.assertIn('budget', self.cli('packet', 'TASK-one', '--role', 'worker', '--max-bytes', '20', ok=False))
        self.mutate(base_sha='0' * 40)
        self.cli('validate', ok=False)


if __name__ == '__main__':
    unittest.main()
