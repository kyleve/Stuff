"""CircleCI continuation transport. Credentials never follow redirects."""

import json
from urllib.request import HTTPRedirectHandler, build_opener


class NoRedirects(HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        return None


def request_json(request):
    with build_opener(NoRedirects).open(request, timeout=120) as response:
        return json.load(response)
