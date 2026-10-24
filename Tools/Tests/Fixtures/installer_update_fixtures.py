"""Public catalog fixtures shared by site validation and local visual previews."""

from Tools.InstallerKit.github_releases import asset_url
from Tools.InstallerKit.installer_installation import manifest_url


REPO = "fixture/Stuff"
FEED_URL = "https://fixture.github.io/Stuff/updates.json"


def catalog(app_id="where", name="Where Dev", bundle_identifier="com.stuff.where.development"):
    channels = []
    for channel in ("main", "pr-42"):
        releases = []
        for run in (2, 1):
            identifier = {"run": run, "attempt": 1}
            releases.append({"id": identifier, "sha": str(run) * 40,
                             "publishedAt": "2026-10-18T00:00:00Z",
                             "manifestURL": manifest_url(FEED_URL, app_id, channel, identifier),
                             "ipaURL": asset_url(REPO, app_id, channel, identifier), "bundleVersion": "1",
                             "buildDetails": {"version": "0.9.2", "minimumOSVersion": "27.0", "sizeBytes": 48300000},
                             "baseSHA": "1" * 40 if run > 1 else None, "historyChanged": False,
                             "commits": [{"sha": str(run) * 40, "subject": "Show <script> & commit notes"}]})
        channels.append({"name": channel, "active": True, "releases": releases})
    return {"schemaVersion": 3, "apps": [{"id": app_id, "name": name,
            "bundleIdentifier": bundle_identifier, "channels": channels}]}


def multiple_apps():
    result = catalog()
    result["apps"] += catalog("example", "Example Dev", "com.example.development")["apps"]
    return result


def site_scenarios():
    """The same deterministic catalogs drive local previews and WebKit snapshots."""
    from copy import deepcopy
    import hashlib

    # Long release notes exercise wrapping and scrolling. Hashes give these
    # synthetic commits stable identities; they do not name repository commits.
    full = multiple_apps()
    for channel in full["apps"][0]["channels"]:
        channel["releases"][0]["commits"] = [
            {"sha": hashlib.sha1(subject.encode()).hexdigest(), "subject": subject}
            for subject in [
                "Install development updates directly from Settings",
                "Keep the update badge visible until the newer build is installed",
                "Show every incoming commit, including changes from skipped builds",
                "Improve long region names on narrow screens and large displays",
                "Preserve the last successful update check while offline",
                "Keep main and pull request builds available from the install site",
                "Clarify installation confirmation and preserve existing Where Dev data",
                "Retain complete release notes when several builds arrive between checks",
            ]
        ]
    # Copy each state so one preview cannot change another fixture.
    unavailable = deepcopy(full)
    unavailable["apps"][0]["channels"][1]["releases"][0]["historyChanged"] = True
    retired = deepcopy(unavailable)
    retired["apps"][0]["channels"][1]["active"] = False
    legacy = catalog("example", "Example Development With a Longer Name", "com.example.development")
    legacy["apps"][0]["channels"] = legacy["apps"][0]["channels"][1:]
    for release in legacy["apps"][0]["channels"][0]["releases"]:
        del release["buildDetails"]
    preparing = deepcopy(full)
    preparing["apps"][0]["channels"][1].update({"active": False, "releases": [],
        "buildStatus": {"state": "preparing", "id": {"run": 3, "attempt": 1}, "sha": "3" * 40}})
    failed = deepcopy(preparing)
    failed["apps"][0]["channels"][1]["buildStatus"]["state"] = "failed"
    rebuilding = deepcopy(full)
    rebuilding["apps"][0]["channels"][1]["buildStatus"] = deepcopy(preparing["apps"][0]["channels"][1]["buildStatus"])
    unpublished = deepcopy(preparing)
    del unpublished["apps"][0]["channels"][1]["buildStatus"]
    return {"full": full, "unavailable-history": unavailable, "retired": retired,
            "empty": {"schemaVersion": 3, "apps": []}, "missing-details": legacy,
            "preparing": preparing, "failed": failed, "rebuilding": rebuilding, "unpublished": unpublished}
