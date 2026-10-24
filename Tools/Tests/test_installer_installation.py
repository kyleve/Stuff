import plistlib
import unittest
from urllib.parse import parse_qs, urlsplit

from Tools.InstallerKit.github_releases import asset_url
from Tools.InstallerKit.installer_apps import load_app
from Tools.InstallerKit.installer_installation import install_url, manifest, manifest_url, site_url, validate_release


class InstallerInstallationTests(unittest.TestCase):
    def test_custom_pages_root_produces_an_exact_build_manifest_and_install_link(self):
        identifier = {"run": 12, "attempt": 2}
        feed = "https://builds.example.org/where/updates.json"
        url = manifest_url(feed, "where", "pr-42", identifier)
        self.assertEqual(url, "https://builds.example.org/where/manifests/where/pr-42/12-2.plist")
        link = urlsplit(install_url(url))
        self.assertEqual(link.scheme, "itms-services")
        self.assertEqual(parse_qs(link.query), {"action": ["download-manifest"], "url": [url]})
        release = {"id": identifier, "manifestURL": url,
                   "ipaURL": asset_url("fixture/Stuff", "where", "pr-42", identifier), "bundleVersion": "2.3.4"}
        validate_release(release, "fixture/Stuff", "where", "pr-42", feed)
        original_manifest = manifest(load_app("where").metadata, release)
        release["buildDetails"] = {"version": "0.9.2", "minimumOSVersion": "27.0", "sizeBytes": 48300000}
        release["pullRequestTitle"] = "Fix **refresh** & keep <older builds> working — 更新"
        validate_release(release, "fixture/Stuff", "where", "pr-42", feed)
        self.assertEqual(manifest(load_app("where").metadata, release), original_manifest)
        item = plistlib.loads(manifest(load_app("where").metadata, release))["items"][0]
        self.assertEqual(item["assets"], [{"kind": "software-package", "url": release["ipaURL"]}])
        self.assertEqual(item["metadata"], {"bundle-identifier": "com.stuff.where.development", "bundle-version": "2.3.4",
                                             "kind": "software", "title": "Where Dev"})

    def test_invalid_titles_and_titles_on_main_are_rejected(self):
        feed = "https://example.org/updates.json"
        identifier = {"run": 12, "attempt": 2}
        for channel, title in (("pr-42", ""), ("pr-42", " \n"), ("pr-42", 42), ("main", "PR title")):
            release = {"id": identifier, "manifestURL": manifest_url(feed, "where", channel, identifier),
                       "ipaURL": asset_url("fixture/Stuff", "where", channel, identifier), "bundleVersion": "1",
                       "pullRequestTitle": title}
            with self.subTest(channel=channel, title=title), self.assertRaises(ValueError):
                validate_release(release, "fixture/Stuff", "where", channel, feed)

    def test_unsafe_feed_locations_and_channel_paths_are_rejected(self):
        for url in ("http://example.org/updates.json", "https://user@example.org/updates.json",
                    "https://example.org:443/updates.json", "https://example.org/updates.json?x=1",
                    "https://example.org/updates.json#x", "https://example.org/../updates.json",
                    "https://example.org/%2e%2e/updates.json", "https://example.org/catalog.json"):
            with self.subTest(url=url), self.assertRaises(ValueError):
                site_url(url)
        with self.assertRaises(ValueError):
            manifest_url("https://example.org/updates.json", "where", "../main", {"run": 1, "attempt": 1})
