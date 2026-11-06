"""Offline CircleCI responses and a signed-identity IPA fixture."""

from Tools.InstallerKit.circleci_archive import ArchiveRequest
from Fixtures.where_distribution_fixtures import SHA, write_ipa


def archive_request():
    return ArchiveRequest(
        "fixture/Stuff",
        "where",
        SHA,
        "pr-42",
        "12",
        "2",
        "https://fixture.github.io/Stuff/updates.json",
    )


def write_archive(path, changes=None):
    request = archive_request()
    write_ipa(
        path,
        {
            "InstallerRepositoryURL": f"https://github.com/{request.repository}",
            "InstallerChannel": request.channel,
            "InstallerRun": request.run,
            "InstallerAttempt": request.attempt,
            "InstallerFeedURL": request.feed_url,
            **(changes or {}),
        },
    )


def pull_request():
    return {
        "state": "open",
        "labels": [{"name": "installable"}],
        "mergeable": True,
        "base": {"repo": {"full_name": "fixture/Stuff"}},
        "head": {"sha": SHA, "repo": {"full_name": "fixture/Stuff"}},
    }
