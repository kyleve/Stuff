"""Publish a generated Pages branch with a lease, then verify its deployment."""

from datetime import datetime, timezone
import os
from pathlib import Path
import re
import subprocess
import sys
import tempfile
import time
from uuid import uuid4

from Tools.InstallerKit.installer_update_feed import GitHubUpdateFeed
from Tools.InstallerKit.installer_update_site import render_site, write_site
from Tools.flyover_pages import compose
from Tools.flyover_retention import prune


BRANCH = "gh-pages"


def branch_head(feed):
    ref = feed.request("GET", f"git/ref/heads/{BRANCH}", allow_missing=True)
    if ref is None:
        return ""
    sha = ref["object"]["sha"]
    if not re.fullmatch(r"[0-9a-f]{40}", sha):
        raise ValueError("Invalid Pages branch commit")
    return sha


def push_site(output, repository, expected, token, run=subprocess.run):
    """Replace only the generated branch, without storing the token or site history."""
    if not re.fullmatch(r"[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+", repository):
        raise ValueError("Invalid repository")
    if expected and not re.fullmatch(r"[0-9a-f]{40}", expected):
        raise ValueError("Invalid expected branch commit")
    if not token or not (output / "index.html").is_file():
        raise ValueError("A complete site and publication credential are required")
    if any(path.is_symlink() or path.name == ".git" for path in output.rglob("*")):
        raise ValueError("Generated site cannot contain links or Git metadata")
    (output / ".nojekyll").touch()
    with tempfile.TemporaryDirectory(prefix="pages-git-") as temporary:
        helper = Path(temporary) / "askpass"
        helper.write_text(
            '#!/bin/sh\ncase "$1" in *Username*) echo x-access-token;; *) printf "%s\\n" "$GH_TOKEN";; esac\n'
        )
        helper.chmod(0o700)
        environment = {
            **os.environ,
            "GH_TOKEN": token,
            "GIT_ASKPASS": str(helper),
            "GIT_TERMINAL_PROMPT": "0",
            "GIT_CONFIG_NOSYSTEM": "1",
            "GIT_CONFIG_GLOBAL": "/dev/null",
        }

        def git(*arguments):
            return run(
                ["git", *arguments],
                cwd=output,
                env=environment,
                check=True,
                text=True,
                capture_output=True,
            ).stdout.strip()

        git("init", "--quiet")
        git("config", "user.name", "Stuff publication")
        git("config", "user.email", "publication@users.noreply.github.com")
        git("config", "core.hooksPath", "/dev/null")
        git("add", "--all")
        tree = git("write-tree")
        # No parent: generated images must not accumulate in repository history.
        commit = git("commit-tree", tree, "-m", f"Publish app install site ({uuid4()})")
        git(
            "push",
            f"--force-with-lease=refs/heads/{BRANCH}:{expected}",
            f"https://github.com/{repository}.git",
            f"{commit}:refs/heads/{BRANCH}",
        )
        return commit


def wait_for_deployment(feed, commit, *, clock=time.monotonic, sleep=time.sleep):
    """Only the exact successful deployment authorizes release retention."""
    deadline = clock() + 600
    while clock() < deadline:
        if branch_head(feed) != commit:
            return False  # A newer complete site owns deployment and retention.
        result = feed.request("GET", f"commits/{commit}/status")
        if result.get("sha") != commit:
            raise ValueError("GitHub returned a different site commit")
        statuses = [
            status
            for status in result["statuses"]
            if status["context"] == "pages-publication"
        ]
        if statuses and statuses[0]["state"] == "success":
            return True
        if statuses and statuses[0]["state"] in ("error", "failure"):
            raise ValueError("Pages deployment failed")
        sleep(5)
    raise TimeoutError("Pages did not confirm deployment within ten minutes")


def deploy(feed, feed_url, token, current, *, push=push_site, wait=wait_for_deployment):
    settings = feed.request("GET", "pages")
    if settings.get("build_type") != "workflow":
        raise ValueError("Pages must use the Deploy Pages workflow")
    for _ in range(5):
        # Read the lease BEFORE reading source state. A competitor's commit forces
        # us to rebuild from the latest catalog/releases rather than push old HTML.
        previous = branch_head(feed)
        if not current():
            return False
        with tempfile.TemporaryDirectory(prefix="pages-deployment-") as temporary:
            output = Path(temporary) / "site"
            catalog = feed.load_for_deployment()
            write_site(render_site(catalog, feed.repository, feed_url), output)
            release = compose(output, feed.repository)
            if not current():
                return False
            try:
                commit = push(output, feed.repository, previous, token)
            except subprocess.CalledProcessError:
                if branch_head(feed) != previous:
                    continue
                raise
        feed.request(
            "POST",
            "dispatches",
            {"event_type": "pages-publication"},
        )
        if wait(feed, commit):
            if release is not None:
                prune(feed.repository, release, datetime.now(timezone.utc))
            return True
        return False
    raise ValueError("Pages branch changed repeatedly; retry publication")


def main():
    try:
        token = os.environ["GH_TOKEN"]
        feed = GitHubUpdateFeed(os.environ["GITHUB_REPOSITORY"], token)
        source = subprocess.check_output(
            ["git", "rev-parse", "HEAD"], text=True
        ).strip()
        confirmed = deploy(
            feed,
            os.environ["INSTALLER_FEED_URL"],
            token,
            lambda: (
                feed.request("GET", "git/ref/heads/main")["object"]["sha"] == source
            ),
        )
    except Exception as error:
        # Git output and HTTP response data can contain credentials.
        print(f"Pages publication failed ({type(error).__name__}).", file=sys.stderr)
        return 1
    print(
        "Pages deployment confirmed."
        if confirmed
        else "Pages deployment superseded by a newer complete site."
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
