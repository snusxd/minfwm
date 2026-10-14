#!/usr/bin/env python3
"""Offline attribution declarations. Local hooks are not an AI participation detector."""
import argparse
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import uuid

POLICY_ROOT = Path(__file__).resolve().parents[1]
REGISTRY = {}
MANAGED = {'ai-tools', 'ai-record'}
TRAILER = re.compile(r'^([A-Za-z0-9-]+)\s*:\s*(.*)$')
RECORD_ID = re.compile(r'^[0-9a-f]{32}$')
SUBJECT = re.compile(r'^(feat|fix|build|chore|docs|refactor|perf|test|ci|style|revert)(\([^\r\n()]+\))?!?: [^\r\n]+$')


class Error(Exception):
    pass


def git(*args, check=True, input=None):
    result = subprocess.run(['git', *args], input=input, stdout=subprocess.PIPE,
                            stderr=subprocess.PIPE)
    if check and result.returncode:
        raise Error(result.stderr.decode('utf-8', 'replace').strip() or 'git command failed')
    return result


def output(*args):
    return git(*args).stdout.decode('utf-8').strip()


def root():
    return Path(output('rev-parse', '--show-toplevel'))


def safe_path(path, anchor):
    """Reject checkout-controlled symlinks before accessing attribution files."""
    anchor = Path(os.path.abspath(anchor))
    path = Path(os.path.abspath(path))
    if anchor.is_symlink():
        raise Error('symlink attribution root is unsupported: ' + str(anchor))
    try:
        relative = path.relative_to(anchor)
        path.resolve().relative_to(anchor.resolve())
    except ValueError as exc:
        raise Error('attribution path escapes its root: ' + str(path)) from exc
    current = anchor
    for part in relative.parts:
        current = current / part
        if current.is_symlink():
            raise Error('symlink attribution path is unsupported: ' + str(current))
    return path


def state_path(name):
    # --absolute-git-dir is worktree-specific; --git-common-dir is deliberately unused.
    directory = Path(output('rev-parse', '--absolute-git-dir'))
    return safe_path(directory / ('minfwm-ai-' + name + '.json'), directory)


def write_json(path, value, anchor=None):
    if anchor is None:
        anchor = Path(output('rev-parse', '--absolute-git-dir'))
    path = safe_path(path, anchor)
    path.parent.mkdir(parents=True, exist_ok=True)
    safe_path(path, anchor)
    temporary = path.with_name(path.name + '.' + uuid.uuid4().hex + '.tmp')
    # Exclusive creation cannot follow a preexisting temporary-file symlink.
    descriptor = os.open(temporary, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    try:
        with os.fdopen(descriptor, 'w', encoding='utf-8') as stream:
            stream.write(json.dumps(value, indent=2, sort_keys=True) + '\n')
        safe_path(path, anchor)
        os.replace(temporary, path)
    finally:
        temporary.unlink(missing_ok=True)


def read_json(path):
    try:
        return json.loads(path.read_text(encoding='utf-8'))
    except (ValueError, UnicodeError, OSError) as exc:
        raise Error('invalid JSON at ' + str(path) + ': ' + str(exc)) from exc


def tools_value(value):
    if not isinstance(value, str) or any(ord(c) < 32 or ord(c) == 127 for c in value):
        raise Error('tool declaration must be one line')
    values = [item.strip().lower() for item in value.split(',')]
    if values == ['none']:
        return []
    if not values or any(item not in REGISTRY for item in values):
        raise Error('unknown or empty tool; expected ' + ', '.join(REGISTRY) + ' or none')
    return sorted(set(values))


def checked_tools(values):
    if not isinstance(values, list) or any(not isinstance(v, str) or v not in REGISTRY for v in values):
        raise Error('invalid participant list')
    if values != sorted(set(values)):
        raise Error('participants must be sorted and unique')
    return values


def task_value(value):
    if not isinstance(value, str) or not re.fullmatch(r'[A-Za-z0-9][A-Za-z0-9_.-]{0,127}', value):
        raise Error('task must be a single safe identifier (max 128 characters)')
    return value


def identity(tool):
    entry = REGISTRY[tool]
    return entry['name'] + ' <' + entry['email'] + '>'


def ai_identity(value):
    match = re.fullmatch(r'\s*([^<>\r\n]+?)\s*<([^<>\s]+)>\s*', value)
    if not match:
        raise Error('invalid Co-authored-by value')
    name, email = match.groups()
    for tool, entry in REGISTRY.items():
        if email.lower() == entry['email'].lower():
            return tool
        if name.strip().lower() == entry['name'].lower():
            raise Error('noncanonical AI identity: ' + value)
    if email.lower().endswith('@ai.invalid'):
        raise Error('unregistered AI identity: ' + value)
    return None


def parse_message(message):
    if '\x00' in message or any(ord(c) < 32 and c not in '\n\r\t' for c in message):
        raise Error('control characters in commit message')
    message = message.replace('\r\n', '\n')
    if '\r' in message:
        raise Error('bare CR in commit message')
    # Git is the authority for whether the last paragraph is a trailer block.
    parsed = git('interpret-trailers', '--parse', input=message.encode()).stdout.decode('utf-8')
    trailers = []
    body = message.rstrip('\n')
    if parsed:
        lines = body.splitlines()
        start = len(lines)
        while start and lines[start - 1].strip():
            start -= 1
        for line in lines[start:]:
            match = TRAILER.fullmatch(line)
            if not match:
                raise Error('multiline or malformed trailer block is unsupported')
            trailers.append((match[1], match[2]))
        body = '\n'.join(lines[:start]).rstrip('\n')
    for line in body.splitlines():
        match = TRAILER.fullmatch(line)
        if match and match[1].lower() in MANAGED:
            raise Error('AI declarations must be in the final trailer block')
    return body, trailers


def declaration(trailers, required=True):
    values = [value for key, value in trailers if key.lower() == 'ai-tools']
    if not values and not required:
        return None
    if len(values) != 1:
        raise Error('exactly one AI-Tools trailer is required; register a session or use tools/ai-commit')
    participants = tools_value(values[0])
    coauthors = [ai_identity(value) for key, value in trailers if key.lower() == 'co-authored-by']
    ai = [tool for tool in coauthors if tool]
    if len(ai) != len(set(ai)):
        raise Error('duplicate AI coauthor')
    if set(ai) != set(participants):
        raise Error('AI-Tools and canonical AI coauthors disagree')
    for key, value in trailers:
        if key.lower() == 'co-authored-by' and ai_identity(value) and value != identity(ai_identity(value)):
            raise Error('AI coauthor must use canonical identity')
    return participants


def load_session():
    path = state_path('session')
    if not path.exists():
        raise Error('no AI session registered in this worktree; run session --tools codex or session --human')
    value = read_json(path)
    if not isinstance(value, dict) or value.get('schema_version') != 1:
        raise Error('invalid session schema')
    checked_tools(value.get('tools'))
    task_value(value.get('task'))
    return value


def load_pending():
    path = state_path('pending')
    if not path.exists():
        return None
    value = read_json(path)
    if not isinstance(value, dict) or not RECORD_ID.fullmatch(value.get('record_id', '')):
        raise Error('invalid pending state')
    checked_tools(value.get('tools'))
    if not isinstance(value.get('tree'), str):
        raise Error('invalid pending tree')
    return value


def record_path(record_id):
    if not RECORD_ID.fullmatch(record_id):
        raise Error('invalid AI-Record identifier')
    return '.agents/contributions/' + record_id + '.json'


def record_from_tree(tree, record_id):
    data = git('show', tree + ':' + record_path(record_id)).stdout
    try:
        record = json.loads(data)
    except (ValueError, UnicodeError) as exc:
        raise Error('invalid contribution record') from exc
    if not isinstance(record, dict):
        raise Error('record must be an object')
    if record.get('schema_version') != 1 or record.get('id') != record_id:
        raise Error('record ID/schema mismatch')
    checked_tools(record.get('tools'))
    task_value(record.get('task'))
    if record.get('assistance') != ('ai' if record['tools'] else 'none'):
        raise Error('record assistance mismatch')
    paths = record.get('paths')
    if not isinstance(paths, list) or any(not isinstance(p, str) or not p or '\x00' in p for p in paths):
        raise Error('invalid record paths')
    if paths != sorted(set(paths)):
        raise Error('record paths must be sorted and unique')
    if 'sources' in record:
        sources = record['sources']
        if not isinstance(sources, list) or not sources or any(
                not isinstance(sha, str) or not re.fullmatch(r'[0-9a-f]{40}|[0-9a-f]{64}', sha)
                for sha in sources) or len(sources) != len(set(sources)):
            raise Error('invalid source commit declaration')
    return record


def changed_paths(base, tree):
    if base:
        data = git('diff', '--name-only', '-z', base, tree, '--').stdout
    else:
        data = git('ls-tree', '-r', '--name-only', '-z', tree).stdout
    return sorted(p.decode('utf-8') for p in data.split(b'\0') if p and not p.startswith(b'.agents/contributions/'))


def validate(message, tree=None, base=None):
    body, trailers = parse_message(message)
    subject = body.splitlines()[0] if body else ''
    if not SUBJECT.fullmatch(subject) and not subject.startswith(('Merge ', 'Revert "', 'fixup! ', 'squash! ')):
        raise Error('expected a Conventional Commit subject')
    participants = declaration(trailers)
    records = [v for k, v in trailers if k.lower() == 'ai-record']
    if len(records) > 1:
        raise Error('duplicate AI-Record trailer')
    if records:
        if tree is None:
            tree = output('write-tree')
        record = record_from_tree(tree, records[0])
        if record['tools'] != participants:
            raise Error('record participants disagree with message')
        if base is None:
            base = record.get('base')
        if record.get('base') != base:
            raise Error('record base disagrees with commit parent')
        if record['paths'] != changed_paths(base, tree):
            raise Error('record paths disagree with commit slice')
    return participants


def squash_message_exists():
    return Path(output('rev-parse', '--git-path', 'SQUASH_MSG')).exists()


def prepare(path, source='', commit=''):
    path = Path(path)
    message = path.read_text(encoding='utf-8')
    body, trailers = parse_message(message)
    pending = load_pending()
    if not pending and squash_message_exists():
        raise Error('local squash requires tools/ai-commit --squash-from REF -- -m SUBJECT')
    if pending:
        if output('write-tree') != pending['tree']:
            raise Error('staged tree changed after attribution freeze; retry tools/ai-commit')
        participants = checked_tools(pending['tools'])
        record_id = pending['record_id']
    else:
        participants = load_session()['tools']
        record_id = None
    # Existing AI credits survive reused/amended messages; human credits remain intact.
    existing = set()
    for key, value in trailers:
        if key.lower() == 'co-authored-by':
            tool = ai_identity(value)
            if tool:
                existing.add(tool)
    if pending and existing - set(participants):
        raise Error('reused message has participants absent from frozen record; declare their union')
    participants = sorted(set(participants) | existing)
    retained = [(k, v) for k, v in trailers if k.lower() not in MANAGED and
                not (k.lower() == 'co-authored-by' and ai_identity(v))]
    if pending:
        for value in pending.get('human_coauthors', []):
            if ai_identity(value):
                raise Error('pending human credit contains an AI identity')
            if not any(k.lower() == 'co-authored-by' and v == value for k, v in retained):
                retained.append(('Co-authored-by', value))
    retained.append(('AI-Tools', ', '.join(participants) or 'none'))
    if record_id:
        retained.append(('AI-Record', record_id))
    retained.extend(('Co-authored-by', identity(tool)) for tool in participants)
    path.write_text(body + '\n\n' + '\n'.join(k + ': ' + v for k, v in retained) + '\n', encoding='utf-8')


def check_commit_message(path):
    pending = load_pending()
    tree = output('write-tree')
    if pending and tree != pending['tree']:
        raise Error('staged tree changed after attribution freeze')
    message = Path(path).read_text(encoding='utf-8')
    participants = validate(message, tree, pending.get('base') if pending else None)
    if pending:
        _, trailers = parse_message(message)
        if ('AI-Record', pending['record_id']) not in trailers or participants != pending['tools']:
            raise Error('frozen record/declaration removed or modified')
    else:
        session = load_session()
        if not set(session['tools']).issubset(participants):
            raise Error('registered participants removed from commit message')


def install():
    checkout = root()
    configured = git('config', '--get', 'core.hooksPath', check=False)
    if configured.returncode == 0 and configured.stdout.decode().strip() != '.githooks':
        raise Error('existing core.hooksPath conflicts; preserved unchanged; integrate dispatcher explicitly')
    native = Path(output('rev-parse', '--absolute-git-dir')) / 'hooks'
    # A linked worktree stores traditional hooks in the common directory.
    common = Path(output('rev-parse', '--git-common-dir'))
    if not common.is_absolute():
        common = checkout / common
    native = common / 'hooks'
    active = [p.name for p in native.glob('*') if p.is_file() and not p.name.endswith('.sample') and os.access(p, os.X_OK)]
    if active and configured.returncode != 0:
        raise Error('existing native hooks preserved; dispatcher integration required: ' + ', '.join(active))
    for name in ('prepare-commit-msg', 'commit-msg'):
        path = checkout / '.githooks' / name
        if not path.is_file() or not os.access(path, os.X_OK):
            raise Error('missing executable hook: ' + str(path))
    git('config', '--local', 'core.hooksPath', '.githooks')
    print('Installed repository-local hooks; register a session in each worktree.')


def doctor():
    if output('config', '--get', 'core.hooksPath') != '.githooks':
        raise Error('hooks are not installed; run install')
    checkout = root()
    for name in ('prepare-commit-msg', 'commit-msg'):
        if not os.access(checkout / '.githooks' / name, os.X_OK):
            raise Error('hook is not executable: ' + name)
    session = load_session()
    # Run the actual configured hook, against a disposable message only; no index mutation.
    probe = state_path('doctor-message')
    if load_pending():
        raise Error('pending wrapper attempt exists; finish/reconcile it before doctor')
    probe.write_text('chore: attribution hook probe\n')
    try:
        subprocess.run([str(checkout / '.githooks/prepare-commit-msg'), str(probe)], check=True)
        subprocess.run([str(checkout / '.githooks/commit-msg'), str(probe)], check=True)
    finally:
        probe.unlink(missing_ok=True)
    print(json.dumps({'hooks': 'active probe passed', 'tools': session['tools'], 'task': session['task']}))


def commit_wrapper(args):
    checkout = root()
    safe_path(checkout / '.agents/contributions', checkout)
    state_path('pending')
    state_path('session')
    arguments = args.git_args
    if arguments and arguments[0] == '--':
        arguments = arguments[1:]
    # An allowlist prevents pathspecs, bundled -an flags, alternate indexes, and
    # staging options from silently excluding the record or changing the slice.
    flags = {'--amend', '--allow-empty', '--allow-empty-message', '-e', '--edit',
             '--no-edit', '-s', '--signoff', '--reset-author', '-v', '--verbose', '-q', '--quiet'}
    valued = {'-m', '--message', '-F', '--file', '-C', '--reuse-message', '-c',
              '--reedit-message', '--author', '--date', '--cleanup', '--trailer'}
    reuse = []
    index = 0
    while index < len(arguments):
        arg = arguments[index]
        if arg in flags:
            index += 1
            continue
        option = arg.split('=', 1)[0]
        if option in valued:
            if '=' in arg:
                value = arg.split('=', 1)[1]
            else:
                index += 1
                if index == len(arguments):
                    raise Error('missing value for ' + option)
                value = arguments[index]
            if option in {'-C', '--reuse-message', '-c', '--reedit-message'}:
                reuse.append(value)
            index += 1
            continue
        raise Error('wrapper requires the already staged slice; unsupported commit option: ' + arg)
    if squash_message_exists() and not args.squash_from:
        raise Error('local squash requires --squash-from REF to preserve retained source contributors')
    if args.squash_from and not squash_message_exists():
        raise Error('--squash-from requires a pending local git merge --squash')
    if args.squash_from and '--amend' in arguments:
        raise Error('local squash cannot also amend the previous commit')
    if os.environ.get('GIT_INDEX_FILE'):
        raise Error('wrapper does not support an alternate GIT_INDEX_FILE')
    if output('config', '--get', 'core.hooksPath') != '.githooks':
        raise Error('wrapper requires installed hooks')
    for name in ('prepare-commit-msg', 'commit-msg'):
        if not os.access(root() / '.githooks' / name, os.X_OK):
            raise Error('wrapper requires executable hooks')
    if state_path('pending').exists():
        pending = load_pending()
        head = git('log', '-1', '--format=%B', check=False).stdout.decode('utf-8')
        _, trailers = parse_message(head)
        if ('AI-Record', pending['record_id']) in trailers:
            if output('rev-parse', 'HEAD^{tree}') != pending['tree']:
                raise Error('pending commit tree mismatch; inspect before reset-pending')
            validate(head, 'HEAD', pending.get('base'))
            state_path('pending').unlink()
            print('Reconciled existing attributed commit ' + output('rev-parse', 'HEAD'))
            return
        else:
            raise Error('pending failed attempt retained; inspect index then run reset-pending before retry')
    selected = {'tools': tools_value(args.tools) if args.tools is not None else [], 'task': task_value(args.task or 'unassigned')}
    if args.tools is None and not args.human:
        selected = load_session()
        if args.task:
            selected['task'] = task_value(args.task)
    base_result = git('rev-parse', '--verify', 'HEAD', check=False)
    base = base_result.stdout.decode().strip() if base_result.returncode == 0 else None
    human_coauthors = []
    squash_sources = []
    if args.squash_from:
        if not base:
            raise Error('local squash requires an existing integration HEAD')
        source = output('rev-parse', '--verify', args.squash_from + '^{commit}')
        ancestors = output('merge-base', '--all', base, source).splitlines()
        if len(ancestors) != 1:
            raise Error('local squash requires exactly one common ancestor')
        squash_sources = output('rev-list', '--reverse', ancestors[0] + '..' + source).splitlines()
        if not squash_sources:
            raise Error('local squash source has no retained commits beyond the common ancestor')
        for sha in squash_sources:
            message = output('show', '-s', '--format=%B', sha)
            parents = output('rev-list', '--parents', '-n', '1', sha).split()
            source_tools = validate(message, sha, parents[1] if len(parents) > 1 else None)
            selected['tools'] = sorted(set(selected['tools']) | set(source_tools))
            _, source_trailers = parse_message(message)
            human_coauthors.extend(v for k, v in source_trailers
                                   if k.lower() == 'co-authored-by' and not ai_identity(v))
    if '--amend' in arguments:
        if not base:
            raise Error('cannot amend unborn HEAD')
        old_message = output('show', '-s', '--format=%B', 'HEAD')
        _, old_trailers = parse_message(old_message)
        human_coauthors.extend(v for k, v in old_trailers if k.lower() == 'co-authored-by' and not ai_identity(v))
        old_tools = declaration(old_trailers, required=False)
        if old_tools:
            selected['tools'] = sorted(set(selected['tools']) | set(old_tools))
        parent = git('rev-parse', '--verify', 'HEAD^', check=False)
        base = parent.stdout.decode().strip() if parent.returncode == 0 else None
    for reference in reuse:
        _, reused_trailers = parse_message(output('show', '-s', '--format=%B', reference))
        human_coauthors.extend(v for k, v in reused_trailers if k.lower() == 'co-authored-by' and not ai_identity(v))
        reused_tools = declaration(reused_trailers, required=False)
        if reused_tools:
            selected['tools'] = sorted(set(selected['tools']) | set(reused_tools))
    staged = output('write-tree')
    paths = changed_paths(base, staged)
    if not paths and '--allow-empty' not in arguments and '--amend' not in arguments:
        raise Error('no staged payload changes')
    record_id = uuid.uuid4().hex
    record = {'schema_version': 1, 'id': record_id, 'task': selected['task'],
              'assistance': 'ai' if selected['tools'] else 'none', 'tools': selected['tools'],
              'base': base, 'paths': paths}
    if squash_sources:
        record['sources'] = squash_sources
    path = root() / record_path(record_id)
    write_json(path, record, root())
    os.chmod(path, 0o644)
    git('add', '--', record_path(record_id))
    pending = {'record_id': record_id, 'tools': selected['tools'], 'tree': output('write-tree'), 'base': base, 'human_coauthors': sorted(set(human_coauthors))}
    write_json(state_path('pending'), pending)
    # Hooks see the pending record before Git reads/finalizes the index.
    result = subprocess.run(['git', 'commit', *arguments])
    if result.returncode:
        raise Error('git commit failed; staged record/pending state retained for inspection')
    message = output('show', '-s', '--format=%B', 'HEAD')
    tree = output('rev-parse', 'HEAD^{tree}')
    if tree != pending['tree']:
        raise Error('commit tree differs from frozen index; inspect commit before continuing')
    validate(message, tree, base)
    state_path('pending').unlink()
    print('Attributed commit ' + output('rev-parse', 'HEAD'))


def history(baseline, head):
    baseline = output('rev-parse', '--verify', baseline + '^{commit}')
    head = output('rev-parse', '--verify', head + '^{commit}')
    if git('merge-base', '--is-ancestor', baseline, head, check=False).returncode:
        raise Error('baseline must be an ancestor of head')
    commits = output('rev-list', '--reverse', baseline + '..' + head).splitlines()
    for sha in commits:
        message = output('show', '-s', '--format=%B', sha)
        parent = output('rev-list', '--parents', '-n', '1', sha).split()
        base = parent[1] if len(parent) > 1 else None
        try:
            validate(message, sha, base)
        except Error as exc:
            raise Error(sha + ': ' + str(exc)) from exc
    print('Validated ' + str(len(commits)) + ' commits after baseline ' + baseline)


def main():
    global REGISTRY
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--repo', help='candidate repository to inspect')
    parser.add_argument('--policy-root', help='trusted checkout containing canonical registry')
    commands = parser.add_subparsers(dest='command', required=True)
    commands.add_parser('install')
    commands.add_parser('doctor')
    session = commands.add_parser('session')
    choice = session.add_mutually_exclusive_group(required=True)
    choice.add_argument('--tools')
    choice.add_argument('--human', action='store_true')
    choice.add_argument('--clear', action='store_true')
    session.add_argument('--task', default='unassigned')
    prepare_parser = commands.add_parser('prepare')
    prepare_parser.add_argument('message')
    prepare_parser.add_argument('source', nargs='?', default='')
    prepare_parser.add_argument('commit', nargs='?', default='')
    for command in ('commit-msg', 'check-message'):
        commands.add_parser(command).add_argument('message')
    check = commands.add_parser('check-history')
    check.add_argument('--baseline', required=True)
    check.add_argument('--head', default='HEAD')
    wrapper = commands.add_parser('commit')
    choice = wrapper.add_mutually_exclusive_group()
    choice.add_argument('--tools')
    choice.add_argument('--human', action='store_true')
    wrapper.add_argument('--task')
    wrapper.add_argument('--squash-from', help='retained source ref for pending local merge --squash')
    wrapper.add_argument('git_args', nargs=argparse.REMAINDER)
    commands.add_parser('reset-pending')
    args = parser.parse_args()
    # Resolve both roots in the caller's cwd before changing to the candidate.
    candidate = Path(os.path.abspath(args.repo)) if args.repo else None
    policy = Path(os.path.abspath(args.policy_root)) if args.policy_root else POLICY_ROOT
    registry_path = safe_path(policy / '.agents/ai-contributors.json', policy)
    registry = read_json(registry_path)
    if not isinstance(registry, dict) or registry.get('schema_version') != 1 or not isinstance(registry.get('contributors'), dict):
        raise Error('invalid contributor registry schema')
    REGISTRY = registry['contributors']
    if candidate:
        os.chdir(candidate)
    if args.command == 'install':
        install()
    elif args.command == 'doctor':
        doctor()
    elif args.command == 'session':
        if args.clear:
            state_path('session').unlink(missing_ok=True)
        else:
            value = {'schema_version': 1, 'tools': tools_value(args.tools) if args.tools is not None else [], 'task': task_value(args.task)}
            write_json(state_path('session'), value)
            print(json.dumps(value))
    elif args.command == 'prepare':
        prepare(args.message, args.source, args.commit)
    elif args.command == 'commit-msg':
        check_commit_message(args.message)
    elif args.command == 'check-message':
        validate(Path(args.message).read_text(encoding='utf-8'))
    elif args.command == 'check-history':
        history(args.baseline, args.head)
    elif args.command == 'commit':
        commit_wrapper(args)
    elif args.command == 'reset-pending':
        state_path('pending').unlink(missing_ok=True)
        print('Pending state cleared; staged files/record preserved. Inspect before retry.')


if __name__ == '__main__':
    try:
        main()
    except (Error, OSError, UnicodeError, subprocess.CalledProcessError) as exc:
        print('ai-attribution: ' + str(exc), file=sys.stderr)
        sys.exit(1)
