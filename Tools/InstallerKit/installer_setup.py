"""Prepare signing for a registered app, then enable its existing distribution workflow."""

import argparse
import base64
from contextlib import nullcontext
import json
import os
from pathlib import Path
import re
import subprocess
import sys

from Tools.InstallerKit.installer_apps import archive_product, load_app
from Tools.repository import repository_root
from Tools.InstallerKit.installer_setup_credentials import signing_environment
from Tools.InstallerKit.installer_setup_pr import (
    checkout,
    read_pull_request,
    recheck_pull_request,
    request_publication,
)


class SetupFailure(Exception):
    def __init__(self, message, status=1):
        super().__init__(message)
        self.status = status if status > 0 else 128 - status


def read_command(arguments, root, run):
    # GH_REPO must not redirect setup away from this controller checkout.
    environment = {
        key: value
        for key, value in os.environ.items()
        if key not in ("GH_REPO", "MATCH_PASSWORD", "INSTALLER_API_KEY_PATH")
    }
    result = run(arguments, cwd=root, env=environment, capture_output=True, text=True)
    if result.returncode:
        raise SetupFailure(
            "Could not read GitHub setup information; check gh authentication and repository access.",
            result.returncode,
        )
    return result.stdout.strip()


def check_main(root, repository, app_id, registration, signing, run):
    """Compare both registrations at one exact main revision, including after refresh."""
    revision = read_command(
        ["gh", "api", f"repos/{repository}/commits/main", "--jq", ".sha"], root, run
    )
    if not re.fullmatch(r"[0-9a-f]{40}", revision):
        raise SetupFailure("GitHub did not return an exact main revision")
    values = []
    for name in ("installer-apps.json", "installer-signing-apps.json"):
        content = read_command(
            [
                "gh",
                "api",
                f"repos/{repository}/contents/.github/{name}?ref={revision}",
                "--jq",
                ".content",
            ],
            root,
            run,
        )
        values.append(
            json.loads(base64.b64decode("".join(content.split()), validate=True))
        )
    if (
        not isinstance(values[0], list)
        or not all(isinstance(value, dict) for value in values[0])
        or not isinstance(values[1], dict)
    ):
        raise SetupFailure("GitHub returned invalid app registrations")
    matches = [value for value in values[0] if value.get("id") == app_id]
    if matches != [registration] or values[1].get(app_id) != signing:
        raise SetupFailure(
            "Merge this app's publication and signing registrations into main before setup."
        )


def setup(
    root, app_id, source, dry_run, run=subprocess.run, report=print, *, pr_number=None
):
    if os.environ.get("CI") or os.environ.get("CIRCLECI"):
        raise SetupFailure("Signing setup is local only")
    if pr_number is not None and source is not None:
        raise SetupFailure("--pr and --source cannot be combined")
    if pr_number is None and (source is None or not (source / "ide").is_file()):
        raise SetupFailure("Source directory does not contain ide")
    apps_path = root / ".github/installer-apps.json"
    signing_path = root / ".github/installer-signing-apps.json"
    app = load_app(app_id, apps_path)
    archive_product(app_id, apps_path, signing_path)
    registration = next(
        value for value in json.loads(apps_path.read_text()) if value["id"] == app_id
    )
    signing = json.loads(signing_path.read_text())[app_id]
    repository = read_command(
        ["gh", "repo", "view", "--json", "nameWithOwner", "--jq", ".nameWithOwner"],
        root,
        run,
    )
    if not re.fullmatch(
        r"[A-Za-z0-9_-][A-Za-z0-9_.-]*/[A-Za-z0-9_-][A-Za-z0-9_.-]*", repository
    ):
        raise SetupFailure("GitHub did not identify this controller's repository")
    check_main(root, repository, app_id, registration, signing, run)
    variable = f"{app.id.upper().replace('-', '_')}_DISTRIBUTION_ENABLED"

    def command(arguments, cwd=root):
        environment = {
            key: value
            for key, value in os.environ.items()
            if key not in ("GH_REPO", "MATCH_PASSWORD", "INSTALLER_API_KEY_PATH")
        }
        environment["GIT_LFS_SKIP_SMUDGE"] = "1"
        result = run(
            arguments, cwd=cwd, env=environment, capture_output=True, text=True
        )
        if result.returncode:
            raise SetupFailure(
                f"{arguments[0]} failed during PR setup. Check tool access and rerun setup.",
                result.returncode,
            )
        return result.stdout.strip()

    pr = (
        read_pull_request(repository, pr_number, command)
        if pr_number is not None
        else None
    )
    if pr:
        from Tools.InstallerKit.installer_distribution import (
            Publication,
            source_available,
        )

        if not source_available(
            app,
            Publication(pr.sha, pr.number),
            repository,
            lambda path: json.loads(command(["gh", "api", path])),
        ):
            raise SetupFailure(
                "The selected PR does not contain this app's registered source directory"
            )
    report(f"Verified {app.name} registration on {repository} main.")
    description = f"PR #{pr.number} at {pr.sha}" if pr else str(source)
    report(f"Refresh signing profiles from {description}, then set {variable}=true.")
    if pr:
        report(
            "Prepare a temporary PR checkout and request publication for all enabled apps present on that PR."
        )
    if dry_run:
        report("Dry run: no signing assets or repository variables changed.")
        return

    credentials = signing_environment()
    if pr:
        report(f"Preparing PR #{pr.number} source and tools.")
    with checkout(root, pr, command) if pr else nullcontext(source) as source:
        if pr:
            pr = recheck_pull_request(pr, command)
        refreshed = run(
            [
                str(root / "signing"),
                "refresh",
                "--app",
                app_id,
                "--source",
                str(source),
            ],
            cwd=root,
            env=credentials,
        )
        if refreshed.returncode:
            raise SetupFailure(
                "Signing refresh failed. The distribution enable variable was not changed.",
                refreshed.returncode,
            )
        try:
            check_main(root, repository, app_id, registration, signing, run)
            if pr:
                pr = recheck_pull_request(pr, command)
        except (SetupFailure, ValueError, TypeError, KeyError, OSError) as error:
            detail = f" {error}" if isinstance(error, SetupFailure) else ""
            raise SetupFailure(
                "Signing refreshed, but the registration or PR could not be verified again. The enable variable was not changed."
                + detail,
                error.status if isinstance(error, SetupFailure) else 1,
            ) from error
        try:
            enabled = run(
                [
                    "gh",
                    "variable",
                    "set",
                    variable,
                    "--body",
                    "true",
                    "--repo",
                    repository,
                ],
                cwd=root,
                capture_output=True,
                text=True,
            )
        except OSError as error:
            raise SetupFailure(
                "Signing refreshed, but GitHub could not enable distribution. Check gh and rerun setup."
            ) from error
        if enabled.returncode:
            raise SetupFailure(
                "Signing refreshed, but enabling distribution failed. Check GitHub variable permissions and rerun setup.",
                enabled.returncode,
            )
        if pr:
            try:
                request_publication(pr, command)
            except (SetupFailure, ValueError, TypeError, KeyError, OSError) as error:
                raise SetupFailure(
                    "Signing refreshed and distribution is enabled, but publication was not confirmed. "
                    "Check the PR and Actions before retrying.",
                    error.status if isinstance(error, SetupFailure) else 1,
                ) from error
            report(
                f"Requested PR #{pr.number} publication. Check App Dev Distribution and App Install Site before installing."
            )
            return
        report(
            f"Enabled {app.name} distribution. Add installable to its PR, or run App Dev Distribution for main."
        )
        report(
            "Verify the published build on a registered device; setup does not publish or install a build."
        )


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--app", required=True)
    selected = parser.add_mutually_exclusive_group(required=True)
    selected.add_argument("--source", type=Path)
    selected.add_argument("--pr", type=int)
    parser.add_argument("--dry-run", action="store_true")
    args = parser.parse_args(argv)
    try:
        setup(
            repository_root(__file__),
            args.app,
            args.source.resolve() if args.source else None,
            args.dry_run,
            pr_number=args.pr,
        )
    except KeyboardInterrupt:
        print(
            "error: Setup interrupted. Check signing and Actions state before retrying.",
            file=sys.stderr,
        )
        return 130
    except SetupFailure as error:
        print(f"error: {error}", file=sys.stderr)
        return error.status
    except (OSError, ValueError, TypeError, KeyError) as error:
        print(f"error: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
