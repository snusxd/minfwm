#!/usr/bin/env python3
"""Git-canonical task cards with a deliberately local, single-writer runtime."""
import argparse
import contextlib
import datetime
import fcntl
import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import re
import subprocess
import sys
import tempfile
import time
import uuid

STAGES = ('backlog', 'research', 'build', 'review', 'test', 'integrate', 'done')
ROLES = ('worker', 'researcher', 'reviewer', 'tester', 'integrator')
STATUSES = ('ready', 'running', 'blocked', 'retry_wait', 'failed', 'cancelled', 'complete')
TASK_ID = re.compile(r'TASK-[A-Za-z0-9][A-Za-z0-9_-]*\Z')
SHA = re.compile(r'[0-9a-f]{40}\Z')
CARDS = 'docs/ai/tasks'


class WorkflowError(Exception):
    pass


def require(condition, message):
    if not condition:
        raise WorkflowError(message)


def stamp():
    return datetime.datetime.now(datetime.timezone.utc).isoformat()


def read_json(path):
    try:
        return json.loads(path.read_text())
    except (OSError, ValueError) as error:
        raise WorkflowError(f'{path}: {error}') from error


def atomic_json(path, value):
    path.parent.mkdir(parents=True, exist_ok=True)
    fd, name = tempfile.mkstemp(prefix='.workflow-', dir=path.parent)
    try:
        with os.fdopen(fd, 'w') as handle:
            json.dump(value, handle, ensure_ascii=False, indent=2, sort_keys=True)
            handle.write('\n')
            handle.flush()
            os.fsync(handle.fileno())
        os.replace(name, path)
    finally:
        if os.path.exists(name):
            os.unlink(name)


def safe_path(value):
    require(isinstance(value, str) and value and not any(ord(c) < 32 for c in value), 'invalid repository path')
    path = PurePosixPath(value)
    require(not path.is_absolute() and '\\' not in value and all(p not in ('.', '..', '.git') for p in value.split('/')),
            f'unsafe repository path: {value}')
    require(str(path) == value, f'non-canonical repository path: {value}')
    return value


def overlaps(a, b):
    return a == b or a.startswith(b + '/') or b.startswith(a + '/')


class Runtime:
    def __init__(self, repo, checkout=None):
        self.repo = Path(repo).resolve()
        self.git('rev-parse', '--show-toplevel')
        self.repo = Path(self.git('rev-parse', '--show-toplevel').strip())
        location = Path(self.git('rev-parse', '--git-path', 'minfwm/workflow').strip())
        self.local = location if location.is_absolute() else self.repo / location
        self.cards = self.repo / CARDS
        self.checkout = self.repo
        if checkout is not None:
            candidate = Path(checkout).resolve()
            def git_at(path, *args):
                run = subprocess.run(['git', '-C', str(path), *args], capture_output=True, text=True)
                require(run.returncode == 0, run.stderr.strip() or 'invalid candidate checkout')
                return run.stdout.strip()
            candidate = Path(git_at(candidate, 'rev-parse', '--show-toplevel'))
            common = Path(self.git('rev-parse', '--git-common-dir').strip())
            common = common if common.is_absolute() else self.repo / common
            other = Path(git_at(candidate, 'rev-parse', '--git-common-dir'))
            other = other if other.is_absolute() else candidate / other
            require(common.resolve() == other.resolve(), 'candidate checkout is not a linked worktree of the canonical repository')
            self.checkout = candidate

    def candidate_git(self, *args):
        result = subprocess.run(['git', '-C', str(self.checkout), *args], capture_output=True, text=True)
        require(result.returncode == 0, result.stderr.strip() or 'candidate Git command failed')
        return result.stdout

    def git(self, *args, check=True):
        result = subprocess.run(['git', '-C', str(self.repo), *args], capture_output=True, text=True)
        if check:
            require(result.returncode == 0, result.stderr.strip() or 'Git command failed')
        return result.stdout

    def head(self):
        return self.candidate_git('rev-parse', 'HEAD').strip()

    def exists(self, sha, path):
        result = subprocess.run(['git', '-C', str(self.repo), 'cat-file', '-e', f'{sha}:{path}'], capture_output=True)
        return result.returncode == 0

    def digest(self, excluded=()):
        names = self.candidate_git('ls-files', '-z', '--cached', '--others', '--exclude-standard').split('\0')
        digest = hashlib.sha256()
        for name in sorted(set(names) - {''}):
            # Cards are a mutable ledger; proofs cover every other non-ignored file.
            if name.startswith(CARDS + '/') or any(overlaps(name, owned) for owned in excluded):
                continue
            path = self.checkout / name
            digest.update(name.encode() + b'\0')
            if path.is_symlink():
                digest.update(b'link\0' + os.readlink(path).encode())
            elif path.is_file():
                require(path.resolve().is_relative_to(self.checkout), f'path escapes repository through a symlink: {name}')
                digest.update(str(0o755 if path.stat().st_mode & 0o111 else 0o644).encode() + b'\0')
                with path.open('rb') as handle:
                    for block in iter(lambda: handle.read(1024 * 1024), b''):
                        digest.update(block)
            elif not path.exists():
                digest.update(b'deleted')
            else:
                digest.update(b'gitlink-or-directory')
            digest.update(b'\0')
        return digest.hexdigest()

    def committed_digest(self, sha):
        digest = hashlib.sha256()
        records = self.git('ls-tree', '-r', '-z', '--full-tree', sha).split('\0')
        entries = []
        for record in records:
            if not record:
                continue
            metadata, name = record.split('\t', 1)
            mode, kind, object_id = metadata.split(' ')
            if not name.startswith(CARDS + '/'):
                entries.append((name, mode, kind, object_id))
        for name, mode, kind, object_id in sorted(entries):
            digest.update(name.encode() + b'\0')
            if kind == 'blob':
                value = subprocess.check_output(['git', '-C', str(self.repo), 'cat-file', 'blob', object_id])
                if mode == '120000':
                    digest.update(b'link\0' + value)
                else:
                    digest.update(str(int(mode, 8) & 0o777).encode() + b'\0' + value)
            else:
                digest.update(b'gitlink-or-directory')
            digest.update(b'\0')
        return digest.hexdigest()

    def require_clean_candidate(self):
        names = self.candidate_git('diff', '--name-only', '-z', 'HEAD').split('\0')
        names += self.candidate_git('ls-files', '--others', '--exclude-standard', '-z').split('\0')
        require(all(not name or name.startswith(CARDS + '/') for name in names),
                'commit candidate content before finish; dirty files outside task cards are not an accepted SHA')

    def binding(self):
        return {'sha': self.head(), 'digest': self.digest()}

    def load_all(self):
        result = {}
        for path in sorted(self.cards.glob('TASK-*.json')):
            task = read_json(path)
            require(isinstance(task, dict), f'{path}: expected object')
            require(task.get('id') == path.stem, f'{path}: filename/id mismatch')
            result[path.stem] = task
        return result

    def task(self, task_id):
        require(TASK_ID.fullmatch(task_id), 'invalid task ID')
        return read_json(self.cards / f'{task_id}.json')

    def save(self, task, action):
        task['revision'] += 1
        task['history'].append({'at': stamp(), 'action': action, 'attempt': task['execution']['attempt']})
        atomic_json(self.cards / (task['id'] + '.json'), task)

    @contextlib.contextmanager
    def locked(self, coordinator=None):
        self.local.mkdir(parents=True, exist_ok=True)
        with (self.local / 'lock').open('a') as handle:
            try:
                fcntl.flock(handle, fcntl.LOCK_EX | fcntl.LOCK_NB)
            except BlockingIOError as error:
                raise WorkflowError('another coordinator mutation is in progress') from error
            if coordinator is not None:
                require(bool(coordinator.strip()), 'coordinator ID is required')
                path = self.local / 'coordinator.json'
                owner = read_json(path) if path.exists() else {}
                require(owner.get('id') in (None, coordinator) or owner.get('expires', 0) <= time.time(),
                        f'coordinator is owned by {owner.get("id")}')
                atomic_json(path, {'id': coordinator, 'expires': time.time() + 3600})
            try:
                yield
            finally:
                fcntl.flock(handle, fcntl.LOCK_UN)

    def spec_digest(self, task):
        frozen = {key: task[key] for key in ('id', 'base_sha', 'plan', 'spec', 'dependencies', 'owned_paths', 'read_set', 'skills')}
        return hashlib.sha256(json.dumps(frozen, sort_keys=True, separators=(',', ':')).encode()).hexdigest()

    def lease_path(self, task_id):
        require(TASK_ID.fullmatch(task_id), 'invalid task ID')
        return self.local / 'claims' / (task_id + '.json')

    def lease(self, task, token=None):
        path = self.lease_path(task['id'])
        require(path.exists(), 'task has no active claim')
        lease = read_json(path)
        require(task['execution']['status'] == 'running', 'claim no longer running; recover before redispatch')
        require(lease['expires'] > time.time(), 'claim expired; recover before redispatch')
        require(lease['attempt'] == task['execution']['attempt'], 'stale task attempt')
        require(lease.get('spec_digest') == self.spec_digest(task), 'task scope changed after dispatch; recover and redispatch')
        if token is not None:
            require(lease['token'] == token, 'stale fencing token or late result')
        return lease

    def validate(self, tasks=None):
        tasks = self.load_all() if tasks is None else tasks
        for task_id, task in tasks.items():
            require(TASK_ID.fullmatch(task_id) and task.get('id') == task_id, 'invalid task ID')
            require(task.get('schema_version') == 1, f'{task_id}: unsupported schema')
            require(type(task.get('revision')) is int and task['revision'] >= 1, f'{task_id}: invalid revision')
            require(isinstance(task.get('title'), str) and task['title'].strip(), f'{task_id}: missing title')
            require(task.get('stage') in STAGES, f'{task_id}: invalid stage')
            base = task.get('base_sha', '')
            require(isinstance(base, str) and SHA.fullmatch(base), f'{task_id}: full base SHA required')
            require(self.git('rev-parse', '--verify', base + '^{commit}').strip() == base, f'{task_id}: invalid base commit')
            plan = safe_path(task.get('plan'))
            require(self.exists(base, plan), f'{task_id}: plan absent at base: {plan}')
            spec = task.get('spec', {})
            require(isinstance(spec, dict) and isinstance(spec.get('summary'), str) and spec['summary'].strip(), f'{task_id}: summary required')
            acceptance = spec.get('acceptance')
            require(isinstance(acceptance, list) and acceptance and all(isinstance(x, str) and x.strip() for x in acceptance), f'{task_id}: acceptance required')
            deps = task.get('dependencies')
            require(isinstance(deps, list) and len(set(deps)) == len(deps) and all(isinstance(x, str) for x in deps), f'{task_id}: invalid dependencies')
            require(all(x in tasks for x in deps), f'{task_id}: unknown dependency')
            require(task_id not in deps, f'{task_id}: dependency cycle')
            paths = task.get('owned_paths')
            require(isinstance(paths, list), f'{task_id}: owned_paths must be a list')
            seen = []
            for item in paths:
                require(isinstance(item, dict) and item.get('operation') in ('create', 'edit', 'delete'), f'{task_id}: invalid owned operation')
                path = safe_path(item.get('path'))
                require(not any(overlaps(path, other) for other in seen), f'{task_id}: overlapping owned paths')
                seen.append(path)
                exists = self.exists(base, path)
                require(exists != (item['operation'] == 'create'), f'{task_id}: {item["operation"]} conflicts with base path: {path}')
            reads = task.get('read_set')
            require(isinstance(reads, list) and len(set(reads)) == len(reads), f'{task_id}: invalid read_set')
            for path in reads:
                require(self.exists(base, safe_path(path)), f'{task_id}: read_set path absent at base: {path}')
            require(isinstance(task.get('skills'), list) and all(isinstance(x, str) for x in task['skills']), f'{task_id}: invalid skills')
            manual = task.get('manual', {})
            require(isinstance(manual, dict) and manual.get('status') in ('not-required', 'pending', 'passed', 'failed') and isinstance(manual.get('reason'), str) and manual['reason'].strip(), f'{task_id}: manual status and reason required')
            execution = task.get('execution', {})
            require(isinstance(execution, dict) and execution.get('status') in STATUSES and type(execution.get('attempt')) is int and execution['attempt'] >= 0, f'{task_id}: invalid execution')
            for key in ('evidence', 'reviews', 'dispatches', 'history'):
                require(isinstance(task.get(key), list) and all(isinstance(x, dict) for x in task[key]), f'{task_id}: invalid {key}')
            if task['stage'] == 'done':
                require(manual['status'] in ('passed', 'not-required'), f'{task_id}: manual evidence blocks done')
                accepted = task.get('accepted_sha')
                require(isinstance(accepted, str) and SHA.fullmatch(accepted), f'{task_id}: accepted_sha required')
                require(self.git('rev-parse', '--verify', accepted + '^{commit}').strip() == accepted, f'{task_id}: accepted commit missing')
                binding = {'sha': accepted, 'digest': task.get('accepted_digest')}
                require(isinstance(binding['digest'], str) and re.fullmatch(r'[0-9a-f]{64}', binding['digest']), f'{task_id}: accepted digest required')
                require(binding['digest'] == self.committed_digest(accepted), f'{task_id}: accepted digest differs from committed source')
                def matches(record):
                    return record.get('attempt') == execution['attempt'] and record.get('binding') == binding and record.get('spec_digest') == self.spec_digest(task)
                require(any(e.get('kind') == 'full' and e.get('exit_code') == 0 and e.get('command') and e.get('output_sha256') and matches(e) for e in task['evidence']), f'{task_id}: accepted full evidence missing')
                require(any(r.get('spec') == 'pass' and r.get('quality') == 'pass' and r.get('agent') and r.get('agent') != task.get('worker') and matches(r) for r in task['reviews']), f'{task_id}: accepted independent review missing')
                if manual['status'] == 'passed':
                    require(any(e.get('kind') == 'manual' and e.get('status') == 'passed' and matches(e) for e in task['evidence']), f'{task_id}: accepted manual evidence missing')
                require(all(tasks[d]['stage'] == 'done' for d in deps), f'{task_id}: required dependency incomplete')
        visiting, visited = set(), set()
        def visit(task_id):
            require(task_id not in visiting, f'{task_id}: dependency cycle')
            if task_id in visited:
                return
            visiting.add(task_id)
            for dependency in tasks[task_id]['dependencies']:
                visit(dependency)
            visiting.remove(task_id)
            visited.add(task_id)
        for task_id in tasks:
            visit(task_id)
        active = [t for t in tasks.values() if t['execution']['status'] == 'running']
        for index, task in enumerate(active):
            for other in active[index + 1:]:
                require(not any(overlaps(a['path'], b['path']) for a in task['owned_paths'] for b in other['owned_paths']),
                        f'{task["id"]}/{other["id"]}: overlapping active ownership')
        return tasks

    def dependencies_ready(self, task):
        tasks = self.validate()
        require(all(tasks[d]['stage'] == 'done' for d in task['dependencies']), 'all required dependencies must be done')

    def proof(self, task, kind):
        binding = self.binding()
        require(any(e.get('kind') == kind and e.get('exit_code') == 0 and e.get('attempt') == task['execution']['attempt']
                    and e.get('binding') == binding and e.get('spec_digest') == self.spec_digest(task) and e.get('command') and e.get('output_sha256') for e in task['evidence']),
                f'passing {kind} command evidence for actual SHA and current digest required')

    def reviewed(self, task):
        binding = self.binding()
        require(any(r.get('spec') == 'pass' and r.get('quality') == 'pass' and r.get('attempt') == task['execution']['attempt']
                    and r.get('binding') == binding and r.get('spec_digest') == self.spec_digest(task) and r.get('agent') and r.get('agent') != task.get('worker') for r in task['reviews']),
                'independent passing spec and quality review for actual SHA and current digest required')

    def manual_ready(self, task):
        require(task['manual']['status'] in ('passed', 'not-required'), 'manual pending or failed blocks integration/done')
        if task['manual']['status'] == 'passed':
            binding = self.binding()
            require(any(e.get('kind') == 'manual' and e.get('status') == 'passed' and e.get('attempt') == task['execution']['attempt'] and e.get('binding') == binding and e.get('spec_digest') == self.spec_digest(task) for e in task['evidence']), 'manual evidence is stale or missing')


def create(rt, args):
    require(TASK_ID.fullmatch(args.task), 'invalid task ID')
    require(not (rt.cards / (args.task + '.json')).exists(), 'task already exists')
    owned = []
    for value in args.owned:
        operation, separator, path = value.partition(':')
        require(separator, '--owned uses operation:path')
        owned.append({'path': path, 'operation': operation})
    task = dict(schema_version=1, id=args.task, title=args.title, revision=1, stage='backlog',
                base_sha=args.base or rt.head(), plan=args.plan, spec={'summary': args.summary, 'acceptance': args.acceptance},
                dependencies=args.dependency, owned_paths=owned, read_set=args.read, skills=args.skill,
                manual={'status': args.manual, 'reason': args.manual_reason}, execution={'status': 'ready', 'attempt': 0},
                evidence=[], reviews=[], dispatches=[], history=[])
    tasks = rt.load_all()
    tasks[args.task] = task
    rt.validate(tasks)
    atomic_json(rt.cards / (args.task + '.json'), task)
    return task


def packet(rt, args):
    task = rt.task(args.task)
    rt.validate()
    result = {key: task[key] for key in ('id', 'revision', 'title', 'stage', 'base_sha', 'plan', 'spec', 'dependencies', 'owned_paths', 'read_set', 'skills', 'manual', 'execution')}
    result.update(role=args.role, instructions=['AGENTS.md', 'docs/ai/AI-Workflow.md'],
                  dispatch='Coordinator must spawn a fresh host subagent and record its actual ID with claim; this CLI does not spawn agents.',
                  access='read-only' if args.role == 'reviewer' else 'owned paths only',
                  rules=['Read the referenced plan and applicable scoped AGENTS.md files.', 'Return a proposal with evidence; only the coordinator changes stage.', 'Reviewer is read-only and must differ from the worker.'])
    encoded = json.dumps(result, ensure_ascii=False, sort_keys=True)
    require(len(encoded.encode()) <= args.max_bytes, 'packet exceeds byte budget; narrow the task card')
    return result


def claim(rt, args):
    task = rt.task(args.task)
    rt.dependencies_ready(task)
    require(task['stage'] != 'done' and task['execution']['status'] != 'cancelled', 'task is closed')
    require(task['execution']['status'] != 'running', 'task already running; recover an orphaned claim first')
    require(1 <= args.ttl <= 86400, 'ttl must be 1..86400 seconds')
    path = rt.lease_path(task['id'])
    require(not path.exists(), 'claim already exists; release or recover it before redispatch')
    expected = {'researcher': 'research', 'worker': 'build', 'reviewer': 'review', 'tester': 'test', 'integrator': 'integrate'}
    require(task['stage'] == expected[args.role], f'{args.role} requires stage {expected[args.role]}')
    require(args.agent.strip(), 'actual host agent ID required')
    require(args.role != 'reviewer' or args.agent != task.get('worker'), 'worker cannot review its own task')
    for other in rt.validate().values():
        if other['id'] != task['id'] and other['execution']['status'] == 'running':
            require(not any(overlaps(a['path'], b['path']) for a in task['owned_paths'] for b in other['owned_paths']), 'owned paths conflict with active task')
    if args.role == 'worker':
        task['execution']['attempt'] += 1
        task['worker'] = args.agent
    task['execution']['status'] = 'running'
    lease = {'spec_digest': rt.spec_digest(task), 'initial_binding': rt.binding(), 'outside_owned_digest': rt.digest([p['path'] for p in task['owned_paths']]), 'task': task['id'], 'agent': args.agent, 'role': args.role, 'attempt': task['execution']['attempt'],
             'token': uuid.uuid4().hex, 'expires': time.time() + args.ttl, 'base_sha': task['base_sha']}
    task['dispatches'].append({**lease, 'at': stamp()})
    rt.save(task, 'claim ' + args.role)
    atomic_json(path, lease)
    return lease


def transition(rt, args):
    task = rt.task(args.task)
    target, current = args.stage, task['stage']
    allowed = target == 'build' and current in ('research', 'review', 'test', 'integrate') or STAGES.index(target) == STAGES.index(current) + 1
    require(allowed and target != 'done', 'invalid stage transition; use finish for done')
    if target == 'build':
        rt.dependencies_ready(task)
        if current == 'research':
            require(bool(args.reason), 'research completion or not-needed reason required')
    if target == 'review':
        rt.proof(task, 'focused')
    if target == 'test':
        rt.reviewed(task)
    if target == 'integrate':
        rt.dependencies_ready(task)
        rt.reviewed(task)
        rt.proof(task, 'full')
        rt.manual_ready(task)
    require(not rt.lease_path(task['id']).exists(), 'release current claim before changing stage')
    task['stage'] = target
    task['execution']['status'] = 'ready'
    rt.save(task, f'transition {current} -> {target}' + (': ' + args.reason if args.reason else ''))
    return task


def evidence(rt, args):
    task = rt.task(args.task)
    original_card = json.dumps(task, sort_keys=True)
    lease = rt.lease(task, args.token)
    require((args.kind == 'focused' and lease['role'] == 'worker') or (args.kind in ('full', 'manual') and lease['role'] in ('tester', 'integrator')), 'claim role cannot supply this evidence')
    before = rt.binding()
    if lease['role'] == 'worker':
        require(rt.digest([p['path'] for p in task['owned_paths']]) == lease['outside_owned_digest'], 'worker changed content outside owned paths')
    else:
        require(before == lease['initial_binding'], 'read-only test/integration candidate changed after claim')
    record = {'kind': args.kind, 'attempt': lease['attempt'], 'agent': lease['agent'], 'token': lease['token'], 'binding': before, 'spec_digest': rt.spec_digest(task), 'at': stamp()}
    if args.kind == 'manual':
        require(args.status in ('passed', 'failed', 'pending') and args.note, 'manual --status and --note required')
        record.update(status=args.status, note=args.note)
        task['manual'] = {'status': args.status, 'reason': args.note}
    else:
        command = args.command[1:] if args.command[:1] == ['--'] else args.command
        require(bool(command), 'evidence requires an explicit command after --')
        with tempfile.TemporaryFile() as output:
            started = time.time()
            try:
                run = subprocess.run(command, cwd=rt.checkout, stdout=output, stderr=subprocess.STDOUT, timeout=args.timeout, shell=False)
                code = run.returncode
            except subprocess.TimeoutExpired:
                code = 124
            except OSError as error:
                raise WorkflowError(f'cannot run evidence command: {error}') from error
            output.seek(0)
            digest = hashlib.sha256()
            tail = b''
            for block in iter(lambda: output.read(65536), b''):
                digest.update(block)
                tail = (tail + block)[-16384:]
        require(rt.binding() == before, 'command changed the checked tree; rerun on the resulting tree')
        record.update(command=command, exit_code=code, duration_seconds=round(time.time() - started, 3), output_sha256=digest.hexdigest(), output_tail=tail.decode('utf-8', errors='replace'))
    require(json.dumps(rt.task(task['id']), sort_keys=True) == original_card, 'task card changed during evidence command; result rejected')
    rt.lease(task, args.token)  # Expiry fences even a command that started in time.
    task['evidence'].append(record)
    rt.save(task, 'evidence ' + args.kind)
    return record


def review(rt, args):
    task = rt.task(args.task)
    lease = rt.lease(task, args.token)
    require(lease['role'] == 'reviewer' and lease['agent'] != task.get('worker'), 'independent reviewer claim required')
    rt.proof(task, 'focused')
    require(rt.binding() == lease['initial_binding'], 'read-only reviewer candidate changed after claim')
    record = {'agent': lease['agent'], 'attempt': lease['attempt'], 'token': lease['token'], 'binding': rt.binding(), 'spec_digest': rt.spec_digest(task),
              'spec': args.spec, 'quality': args.quality, 'summary': args.summary, 'at': stamp()}
    task['reviews'].append(record)
    rt.save(task, 'review')
    return record


def release(rt, args):
    task = rt.task(args.task)
    rt.lease(task, args.token)
    task['execution']['status'] = 'ready'
    rt.save(task, 'release')
    rt.lease_path(task['id']).unlink()
    return {'released': task['id']}


def recover(rt, args):
    recovered = []
    for task in rt.load_all().values():
        path = rt.lease_path(task['id'])
        lease = read_json(path) if path.exists() else None
        expired = lease and lease['expires'] <= time.time()
        orphan = task['execution']['status'] == 'running' and lease is None
        inconsistent = lease and (lease['attempt'] != task['execution']['attempt'] or task['execution']['status'] != 'running' or lease.get('spec_digest') != rt.spec_digest(task))
        if not (expired or orphan or inconsistent):
            continue
        require(task['stage'] != 'done', 'closed task has inconsistent local claim; inspect it manually')
        task['execution']['status'] = 'retry_wait'
        task['execution']['attempt'] += 1
        rt.save(task, 'recover expired/orphaned claim; previous token fenced')
        if path.exists():
            path.unlink()
        recovered.append(task['id'])
    return {'recovered': recovered}


def finish(rt, args):
    task = rt.task(args.task)
    require(task['stage'] == 'integrate', 'finish requires integrate stage')
    require(not rt.lease_path(task['id']).exists(), 'release integrator claim before finish')
    rt.dependencies_ready(task)
    rt.require_clean_candidate()
    rt.proof(task, 'full')
    rt.reviewed(task)
    rt.manual_ready(task)
    require(rt.digest() == rt.committed_digest(rt.head()), 'candidate digest does not match committed source')
    task.update(stage='done', accepted_sha=rt.head(), accepted_digest=rt.digest(), result=args.summary, usage=args.usage)
    task['execution']['status'] = 'complete'
    rt.save(task, 'finish')
    return task


def parser():
    root = argparse.ArgumentParser(description=__doc__)
    root.add_argument('--repo', default='.')
    root.add_argument('--checkout', help='Linked candidate worktree; canonical cards and claims remain in --repo')
    commands = root.add_subparsers(dest='action', required=True)
    commands.add_parser('validate')
    commands.add_parser('list')
    def task_command(name, coordinator=False):
        sub = commands.add_parser(name)
        sub.add_argument('task')
        if coordinator:
            sub.add_argument('--coordinator', required=True)
        return sub
    sub = task_command('create', True)
    for key in ('title', 'plan', 'summary', 'manual-reason'):
        sub.add_argument('--' + key, required=True)
    sub.add_argument('--acceptance', action='append', required=True)
    sub.add_argument('--owned', action='append', default=[])
    for key in ('read', 'dependency', 'skill'):
        sub.add_argument('--' + key, action='append', default=[])
    sub.add_argument('--base')
    sub.add_argument('--manual', choices=('not-required', 'pending'), default='not-required')
    sub = task_command('packet')
    sub.add_argument('--role', choices=ROLES, required=True)
    sub.add_argument('--max-bytes', type=int, default=12000)
    sub = task_command('claim', True)
    sub.add_argument('--agent', required=True)
    sub.add_argument('--role', choices=ROLES, required=True)
    sub.add_argument('--ttl', type=int, default=3600)
    sub = task_command('transition', True)
    sub.add_argument('stage', choices=STAGES)
    sub.add_argument('--reason', default='')
    sub = task_command('evidence')
    sub.add_argument('--token', required=True)
    sub.add_argument('--kind', choices=('focused', 'full', 'manual'), required=True)
    sub.add_argument('--status', choices=('pending', 'passed', 'failed'))
    sub.add_argument('--note')
    sub.add_argument('--timeout', type=int, default=1800)
    sub = task_command('review')
    sub.add_argument('--token', required=True)
    sub.add_argument('--spec', choices=('pass', 'fail'), required=True)
    sub.add_argument('--quality', choices=('pass', 'fail'), required=True)
    sub.add_argument('--summary', required=True)
    sub = task_command('release', True)
    sub.add_argument('--token', required=True)
    sub = commands.add_parser('recover')
    sub.add_argument('--coordinator', required=True)
    sub = task_command('finish', True)
    sub.add_argument('--summary', required=True)
    sub.add_argument('--usage', default='unavailable')
    return root


def main(argv=None):
    raw = list(sys.argv[1:] if argv is None else argv)
    command = []
    if '--' in raw:
        index = raw.index('--')
        raw, command = raw[:index], raw[index + 1:]
    args = parser().parse_args(raw)
    args.command = command
    try:
        rt = Runtime(args.repo, args.checkout)
        if args.action == 'validate':
            result = {'valid': True, 'tasks': len(rt.validate())}
        elif args.action == 'list':
            result = [{k: t[k] for k in ('id', 'title', 'stage', 'execution')} for t in rt.validate().values()]
        elif args.action == 'packet':
            result = packet(rt, args)
        else:
            with rt.locked(getattr(args, 'coordinator', None)):
                rt.validate()
                result = globals()[args.action](rt, args)
        print(json.dumps(result, ensure_ascii=False, indent=2, sort_keys=True))
        if args.action == 'evidence' and result.get('exit_code', 0):
            return 1
        return 0
    except (WorkflowError, KeyError, TypeError, ValueError) as error:
        print(f'ai-workflow: {error}', file=sys.stderr)
        return 1


if __name__ == '__main__':
    sys.exit(main())
