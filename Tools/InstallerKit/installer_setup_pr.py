"""Prepare an exact same-repository PR checkout and request its installable build."""

from contextlib import contextmanager
from dataclasses import dataclass
import json
from pathlib import Path
import re
import tempfile


@dataclass(frozen=True)
class PullRequest:
    repository: str
    number: int
    sha: str
    installable: bool


def read_pull_request(repository, number, command):
    if type(number) is not int or number < 1:
        raise ValueError('PR number must be a positive integer')
    value = json.loads(command(['gh', 'api', f'repos/{repository}/pulls/{number}']))
    if (value.get('state') != 'open'
            or (value.get('head', {}).get('repo') or {}).get('full_name') != repository
            or (value.get('base', {}).get('repo') or {}).get('full_name') != repository):
        raise ValueError('Setup requires an open PR from this repository; fork PRs cannot receive signing credentials.')
    if value.get('mergeable') is not True:
        raise ValueError('PR mergeability is not confirmed. Resolve conflicts or wait for GitHub, then rerun setup.')
    sha = value.get('head', {}).get('sha')
    if not isinstance(sha, str) or not re.fullmatch(r'[0-9a-f]{40}', sha):
        raise ValueError('GitHub did not return an exact PR head')
    labels = value.get('labels')
    if not isinstance(labels, list) or not all(isinstance(label, dict) for label in labels):
        raise ValueError('GitHub did not return PR labels')
    return PullRequest(repository, number, sha, any(label.get('name') == 'installable' for label in labels))


def recheck_pull_request(pr, command):
    current = read_pull_request(pr.repository, pr.number, command)
    if current.sha != pr.sha or (pr.installable and not current.installable):
        raise ValueError('The PR head or installable label changed during setup. Rerun setup for its current state.')
    return current


@contextmanager
def checkout(root, pr, command):
    # A private clone avoids changing the user's checkout or shared worktree registry.
    # Its object database borrows from root only for this context's lifetime.
    with tempfile.TemporaryDirectory(prefix=f'installer-pr-{pr.number}-') as temporary:
        source = Path(temporary) / 'source'
        command(['git', 'clone', '--shared', '--no-checkout', str(root), str(source)])
        command(['git', '-C', str(source), 'fetch', '--depth=1',
                 f'https://github.com/{pr.repository}.git', pr.sha])
        command(['git', '-C', str(source), '-c', 'core.hooksPath=/dev/null', 'checkout', '--detach', pr.sha])
        actual = command(['git', '-C', str(source), 'rev-parse', 'HEAD']).strip()
        if actual != pr.sha or not (source / 'ide').is_file():
            raise ValueError('PR checkout does not match the requested source')
        # Explicit --pr authorizes the selected source's tool configuration and build scripts.
        command(['mise', 'trust', str(source / '.mise.toml')], cwd=source)
        command(['mise', 'install'], cwd=source)
        yield source


def request_publication(pr, command):
    current = recheck_pull_request(pr, command)
    if current.installable:
        command(['gh', 'workflow', 'run', 'installer-distribution.yml', '--repo', pr.repository,
                 '--ref', 'main', '-f', f'pull_request={pr.number}'])
    else:
        # Adding the label triggers the controller; no separate dispatch or label removal.
        command(['gh', 'pr', 'edit', str(pr.number), '--repo', pr.repository, '--add-label', 'installable'])
