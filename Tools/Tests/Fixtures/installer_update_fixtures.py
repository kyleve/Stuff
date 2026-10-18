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
