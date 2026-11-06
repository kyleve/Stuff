"""Temporary Git history for CI selection and continuation boundary tests."""

from pathlib import Path
import shutil
import subprocess

from Tools.repository import repository_root


class GitRepository:
    def __init__(self, root):
        self.root = Path(root)
        self.git("init", "-b", "main")
        self.git("config", "user.name", "CI Test")
        self.git("config", "user.email", "ci@example.test")
        source = repository_root(__file__)
        for name in ("ci_changes", "ci_circleci", "circleci_pipeline", "repository"):
            target = self.root / f"Tools/{name}.py"
            target.parent.mkdir(exist_ok=True)
            shutil.copyfile(source / f"Tools/{name}.py", target)
        self.write(".circleci/jobs.yml", "version: 2.1\n")
        self.write(".circleci/continue.yml", "workflows: {}\n")
        self.write("README.md", "Original documentation\n")
        self.write("app.py", "original = True\n")
        self.base = self.commit()
        self.git("switch", "-c", "topic")

    def git(self, *args):
        return subprocess.check_output(
            [
                "git",
                "-c",
                "core.hooksPath=/dev/null",
                "-c",
                "commit.gpgsign=false",
                *args,
            ],
            cwd=self.root,
            stderr=subprocess.PIPE,
            text=True,
        ).strip()

    def write(self, name, content):
        path = self.root / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(content)

    def commit(self):
        self.git("add", "--all")
        self.git("commit", "--quiet", "-m", "Fixture commit")
        return self.git("rev-parse", "HEAD")
