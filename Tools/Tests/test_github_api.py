import io
from pathlib import Path
import sys
import unittest
from unittest.mock import patch
from urllib.error import HTTPError
from urllib.request import Request

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from github_api import NoRedirects, request_json


class GitHubAPITests(unittest.TestCase):
    def test_only_explicitly_allowed_missing_responses_are_absorbed(self):
        request = Request("https://api.github.com/test")
        for status in (404, 403, 500):
            with self.subTest(status=status), patch("github_api.build_opener") as opener:
                opener.return_value.open.side_effect = HTTPError(request.full_url, status, "secret", {}, io.BytesIO())
                if status == 404:
                    self.assertIsNone(request_json(request, allow_missing=True))
                else:
                    with self.assertRaisesRegex(ValueError, f"HTTP {status}") as error:
                        request_json(request, allow_missing=True)
                    self.assertNotIn("secret", str(error.exception))
                with self.assertRaises(ValueError):
                    request_json(request)

    def test_redirects_never_forward_credentials(self):
        self.assertIsNone(NoRedirects().redirect_request(None, None, 302, "", {}, "https://other.example"))
