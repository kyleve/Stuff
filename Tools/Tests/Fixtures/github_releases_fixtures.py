"""Stateful GitHub responses for upload, interrupted publication, and retry tests."""

import hashlib
import json

from github_releases import asset_url


class ReleaseServer:
    def __init__(self, asset_changes=None):
        self.requests = []
        self.release = None
        self.assets = []
        self.private = False
        self.fail_upload = False
        self.asset_changes = asset_changes or {}

    def __call__(self, request, **kwargs):
        self.requests.append(request)
        path = request.full_url.split("/repos/fixture/Stuff", 1)[1]
        if path == "":
            return {"private": self.private, "visibility": "private" if self.private else "public"}
        if path == "/git/ref/heads/main":
            return {"object": {"sha": "b" * 40}}
        if path.startswith("/releases/tags/"):
            return self.release if self.release and not self.release["draft"] else None
        if path.startswith("/releases?per_page="):
            return [self.release] if self.release else []
        if path == "/releases" and request.method == "POST":
            self.release = {**json.loads(request.data), "id": 123}
            return self.release
        if path == "/releases/123/assets?per_page=100":
            return self.assets
        if path == "/releases/123/assets?name=app.ipa":
            if self.fail_upload:
                raise ValueError("upload failed")
            asset = {"id": 456, "name": "app.ipa", "size": len(request.data), "state": "uploaded",
                     "digest": "sha256:" + hashlib.sha256(request.data).hexdigest(),
                     "browser_download_url": asset_url("fixture/Stuff", "where", "pr-42", {"run": 12, "attempt": 1}),
                     **self.asset_changes}
            self.assets = [asset]
            return asset
        if path == "/releases/123" and request.method == "PATCH":
            self.release.update(json.loads(request.data))
            return self.release
        raise AssertionError(f"Unexpected request: {request.method} {path}")
