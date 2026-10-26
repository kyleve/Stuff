"""Single-directory atlas publication with explicit recovery ownership.

The two renames are not an atomic exchange. Recovery never overwrites a
destination that appears after the old atlas moves to the private backup.
"""

from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path
import os
import shutil
import signal
import tempfile

from Tools.flyover_manifest import MARKER_CONTENT


@dataclass(frozen=True)
class StagedDirectory:
    path: Path
    identity: os.stat_result

    def is_installed_at(self, destination: Path) -> bool:
        try:
            actual = destination.lstat()
        except FileNotFoundError:
            return False
        return (actual.st_dev, actual.st_ino) == (self.identity.st_dev, self.identity.st_ino)


def resolve_destination(value: str, workspace: Path, *, action: str) -> Path:
    destination = Path(os.path.realpath(os.path.abspath(os.path.expanduser(value))))
    for protected, label in ((Path('/'), 'filesystem root'),
                             (Path.home().resolve(), 'home directory'),
                             (workspace.resolve(), 'workspace root')):
        if destination == protected or (destination.exists() and destination.samefile(protected)):
            raise ValueError(f"refusing to {action} the {label}")
    return destination


def validate_destination(destination: Path) -> None:
    """Only a generated, real directory can be replaced."""
    if not destination.exists() and not destination.is_symlink():
        return
    if destination.is_symlink() or not destination.is_dir():
        raise ValueError(f"refusing to replace non-directory '{destination}'")
    marker = destination / '.flyover-generated'
    if marker.is_symlink():
        raise ValueError(f"refusing to replace directory with a symbolic-link marker '{destination}'")
    if not marker.is_file():
        raise ValueError(f"refusing to replace unmarked directory '{destination}'")
    if marker.read_text(encoding='utf-8').rstrip('\n') != MARKER_CONTENT:
        raise ValueError(f"refusing to replace directory with an unsupported marker '{destination}'")


class AtlasPublication:
    """Own one staging directory and, during replacement, one private backup."""

    def __init__(self, destination: Path):
        self.destination = destination
        self._staged: StagedDirectory | None = None
        self.backup_container: Path | None = None

    @property
    def staging(self) -> Path:
        assert self._staged is not None, 'publication context is not active'
        return self._staged.path

    def __enter__(self) -> AtlasPublication:
        validate_destination(self.destination)
        self.destination.parent.mkdir(parents=True, exist_ok=True)
        staging = Path(tempfile.mkdtemp(prefix='.flyover-staging.', dir=self.destination.parent))
        self._staged = StagedDirectory(staging, staging.stat())
        return self

    def publish(self) -> None:
        (self.staging / '.flyover-generated').write_text(MARKER_CONTENT + '\n', encoding='utf-8')
        for path in (self.staging, *self.staging.rglob('*')):
            path.chmod(0o755 if path.is_dir() else 0o644)
        validate_destination(self.destination)
        if self.destination.exists():
            self.backup_container = Path(tempfile.mkdtemp(
                prefix='.flyover-replacement.', dir=self.destination.parent,
            ))
            os.rename(self.destination, self.backup_container / 'previous')
        os.rename(self.staging, self.destination)
        # Once installed, cleanup must not roll the new atlas back.

    def __exit__(self, error_type, error, traceback):
        # The first interrupt can arrive during ordinary error recovery, before
        # the CLI handler has disabled subsequent interrupts. Defer it until
        # both staging cleanup and backup recovery have finished.
        previous_mask = signal.pthread_sigmask(signal.SIG_BLOCK, {signal.SIGINT, signal.SIGTERM})
        try:
            self._recover(error)
        except BaseException as recovery_error:
            try:
                signal.pthread_sigmask(signal.SIG_SETMASK, previous_mask)
            finally:
                # A pending interrupt must not hide retained-backup diagnostics.
                raise recovery_error
        else:
            signal.pthread_sigmask(signal.SIG_SETMASK, previous_mask)
        return False

    def _recover(self, error):
        failures = []
        if self.staging.exists():
            try:
                shutil.rmtree(self.staging)
            except OSError as cleanup_error:
                failures.append(f"staging cleanup failed at {self.staging}: {cleanup_error}")
        if self.backup_container is not None:
            backup = self.backup_container / 'previous'
            try:
                if backup.exists():
                    if not self.destination.exists() and not self.destination.is_symlink():
                        os.rename(backup, self.destination)
                    elif self._staged.is_installed_at(self.destination):
                        shutil.rmtree(backup)
                    else:
                        raise OSError(f"destination exists; recovery material retained at {backup}")
                self.backup_container.rmdir()
            except OSError as recovery_error:
                failures.append(f"backup recovery or cleanup failed: {recovery_error}")
        if failures:
            detail = '; '.join(failures)
            if error is not None:
                detail = f"{error}; {detail}"
            raise OSError(detail) from error
