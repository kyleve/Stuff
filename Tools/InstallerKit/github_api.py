"""GitHub JSON transport. Never forward credentials through a redirect."""

import json
from urllib.error import HTTPError
from urllib.request import HTTPRedirectHandler, build_opener


# This is GitHub's REST contract version, not the current date. Keep the pin
# until we review the next version's breaking changes. Supported versions:
# https://docs.github.com/en/rest/about-the-rest-api/api-versions
API_VERSION = "2022-11-28"


class NoRedirects(HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        return None


def request_json(request, allow_missing=False):
    try:
        with build_opener(NoRedirects).open(request, timeout=120) as response:
            if response.status == 204:
                return {}
            return json.load(response)
    except HTTPError as error:
        if allow_missing and error.code == 404:
            return None
        # Response bodies and headers can contain credentials or private data.
        raise ValueError(f"{request.host}: HTTP {error.code}") from error
