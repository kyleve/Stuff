"""Publish a signed IPA once per build, verifying the asset before publication."""

import hashlib
import json
import re
from urllib.request import Request

from Tools.InstallerKit.github_api import API_VERSION, request_json
from Tools.InstallerKit.installer_apps import validate_app_id


def release_tag(app_id, channel, identifier):
    validate_app_id(app_id)
    if not re.fullmatch(r"main|pr-[1-9][0-9]*", channel):
        raise ValueError("Invalid distribution channel")
    for key in ("run", "attempt"):
        if type(identifier[key]) is not int or identifier[key] < 1:
            raise ValueError("A positive GitHub run ID and attempt are required")
    return f"installer-{app_id}-{channel}-{identifier['run']}-{identifier['attempt']}"


def asset_url(repository, app_id, channel, identifier):
    if not re.fullmatch(r"[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+", repository):
        raise ValueError("Invalid GitHub repository")
    return f"https://github.com/{repository}/releases/download/{release_tag(app_id, channel, identifier)}/app.ipa"


class GitHubReleases:
    def __init__(self, repository, token, transport=request_json):
        if not re.fullmatch(r"[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+", repository):
            raise ValueError("Invalid GitHub repository")
        if not token or "\n" in token or "\r" in token:
            raise ValueError("GH_TOKEN is required to publish releases")
        self.repository = repository
        self.token = token
        self.transport = transport

    def request(self, method, path, value=None, *, binary=None, allow_missing=False):
        host = "uploads.github.com" if binary is not None else "api.github.com"
        body = binary if binary is not None else json.dumps(value).encode() if value is not None else None
        return self.transport(Request(f"https://{host}/repos/{self.repository}{path}",
                                      method=method, data=body, headers={
                                          "Authorization": f"Bearer {self.token}",
                                          "Accept": "application/vnd.github+json",
                                          "Content-Type": "application/octet-stream" if binary is not None else "application/json",
                                          "X-GitHub-Api-Version": API_VERSION,
                                      }), allow_missing=allow_missing)

    def find(self, tag):
        release = self.request("GET", f"/releases/tags/{tag}", allow_missing=True)
        if release is not None:
            return release
        # The tag endpoint returns published releases. Inspect drafts to recover
        # an interrupted upload without creating duplicate releases.
        page = 1
        while True:
            releases = self.request("GET", f"/releases?per_page=100&page={page}")
            matches = [release for release in releases if release["tag_name"] == tag]
            if len(matches) > 1:
                raise ValueError("Multiple releases use this build tag")
            if matches:
                return matches[0]
            if len(releases) < 100:
                return None
            page += 1

    def publish(self, ipa, app_id, channel, identifier, source_sha, notes):
        tag = release_tag(app_id, channel, identifier)
        expected_url = asset_url(self.repository, app_id, channel, identifier)
        if not re.fullmatch(r"[0-9a-f]{40}", source_sha):
            raise ValueError("Invalid build commit")
        size = ipa.stat().st_size
        if not 0 < size < 2 * 1024 ** 3:
            raise ValueError("Release IPA must be nonempty and smaller than 2 GiB")
        contents = ipa.read_bytes()
        digest = "sha256:" + hashlib.sha256(contents).hexdigest()
        repository = self.request("GET", "")
        if repository.get("visibility") != "public" or repository.get("private") is not False:
            raise ValueError("Direct installation requires a public release repository")
        body = (f"{notes}\n\nSource: https://github.com/{self.repository}/commit/{source_sha}\n"
                f"Build: {identifier['run']}.{identifier['attempt']}\nIPA SHA-256: {digest[7:]}")
        release = self.find(tag)
        if release is None:
            # GITHUB_TOKEN cannot tag PR commits that modify workflow files.
            # The tag anchors publication to trusted main; the IPA stamp and
            # release body identify the actual source revision.
            controller_sha = self.request("GET", "/git/ref/heads/main")["object"]["sha"]
            if not re.fullmatch(r"[0-9a-f]{40}", controller_sha):
                raise ValueError("Invalid controller commit")
            release = self.request("POST", "/releases", {
                "tag_name": tag, "target_commitish": controller_sha,
                "name": f"{app_id} · {channel} · {identifier['run']}.{identifier['attempt']}",
                "body": body, "draft": True, "prerelease": True, "make_latest": "false",
            })
        if release.get("tag_name") != tag or release.get("body") != body or release.get("prerelease") is not True:
            raise ValueError("Existing release does not match this build; refusing to replace it")
        release_id = release["id"]
        if type(release_id) is not int or release_id < 1:
            raise ValueError("Invalid GitHub release identity")
        assets = self.request("GET", f"/releases/{release_id}/assets?per_page=100")
        if len(assets) > 1 or (assets and assets[0].get("name") != "app.ipa"):
            raise ValueError("Unexpected assets in the build release")
        if assets:
            asset = assets[0]
        elif release.get("draft") is True:
            asset = self.request("POST", f"/releases/{release_id}/assets?name=app.ipa", binary=contents)
        else:
            raise ValueError("Published release has no IPA; refusing to modify it")
        if (asset.get("name") != "app.ipa" or asset.get("state") != "uploaded" or asset.get("size") != size
                or asset.get("digest") != digest or asset.get("browser_download_url") != expected_url):
            raise ValueError("Release IPA verification failed; inspect the draft before retrying")
        if release.get("draft") is True:
            release = self.request("PATCH", f"/releases/{release_id}", {"draft": False, "make_latest": "false"})
        if release.get("draft") is not False:
            raise ValueError("GitHub did not publish the release")
        return expected_url
