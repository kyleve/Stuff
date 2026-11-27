import io
import unittest
from unittest.mock import patch
from urllib.error import HTTPError
from urllib.request import Request

from Tools.InstallerKit.github_api import NoRedirects, request_json


class GitHubAPITests(unittest.TestCase):
    def test_only_explicitly_allowed_missing_responses_are_absorbed(self):
        request = Request("https://api.github.com/test")
        for status in (404, 403, 500):
            for allow_missing in (False, True):
                with (
                    self.subTest(status=status, allow_missing=allow_missing),
                    patch("Tools.InstallerKit.github_api.build_opener") as opener,
                ):
                    body = io.BytesIO()
                    failure = HTTPError(request.full_url, status, "secret", {}, body)
                    self.addCleanup(failure.close)
                    opener.return_value.open.side_effect = failure
                    if status == 404 and allow_missing:
                        self.assertIsNone(request_json(request, allow_missing=True))
                    else:
                        with self.assertRaisesRegex(
                            ValueError, f"HTTP {status}"
                        ) as error:
                            request_json(request, allow_missing=allow_missing)
                        self.assertIs(error.exception.__cause__, failure)
                        self.assertNotIn("secret", str(error.exception))
                    self.assertTrue(body.closed)

    def test_redirects_never_forward_credentials(self):
        self.assertIsNone(
            NoRedirects().redirect_request(
                None, None, 302, "", {}, "https://other.example"
            )
        )
