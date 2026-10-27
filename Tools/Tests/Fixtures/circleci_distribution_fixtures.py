"""Offline CircleCI responses and a signed-identity IPA fixture."""

from Tools.InstallerKit.circleci_archive import ArchiveRequest
from Fixtures.where_distribution_fixtures import SHA, write_ipa


PROJECT = "circleci/fixture/project"
PIPELINE = "11111111-1111-4111-8111-111111111111"
WORKFLOW = "22222222-2222-4222-8222-222222222222"
DEFINITION = "33333333-3333-4333-8333-333333333333"
ARTIFACT_URL = "https://output.circle-artifacts.com/fixture/Where.ipa"


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


class CircleCIServer:
    def __init__(self):
        self.requests = []
        self.pipeline = {
            "id": PIPELINE,
            "project_slug": PROJECT,
            "state": "created",
            "errors": [],
        }
        self.workflows = [
            {
                "id": WORKFLOW,
                "pipeline_id": PIPELINE,
                "name": "Installer Archive",
                "status": "success",
            }
        ]
        self.jobs = [{"name": "Archive App", "status": "success", "job_number": 7}]
        self.artifacts = [{"path": "installer/app.ipa", "url": ARTIFACT_URL}]

    def __call__(self, request):
        self.requests.append(request)
        path = request.full_url.removeprefix("https://circleci.com/api/v2/")
        if path == f"project/{PROJECT}/pipeline/run" and request.method == "POST":
            return {"id": PIPELINE}
        if path == f"pipeline/{PIPELINE}":
            return self.pipeline
        if path == f"pipeline/{PIPELINE}/workflow":
            return {"items": self.workflows}
        if path == f"workflow/{WORKFLOW}/job":
            return {"items": self.jobs}
        if path == f"project/{PROJECT}/7/artifacts":
            return {"items": self.artifacts}
        raise AssertionError(f"Unexpected CircleCI request: {request.method} {path}")
