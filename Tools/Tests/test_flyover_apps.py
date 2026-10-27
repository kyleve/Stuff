import json
from pathlib import Path
import tempfile
import unittest

from Tools.flyover_apps import load_app, load_apps


class FlyoverAppsTests(unittest.TestCase):
    def test_registry_supports_multiple_adapters(self):
        with tempfile.TemporaryDirectory() as temporary:
            source = Path(temporary) / "apps.json"
            source.write_text(
                json.dumps(
                    [
                        {
                            "id": app_id,
                            "title": app_id,
                            "testIdentifier": f"{suite}/Export/capture()",
                        }
                        for app_id, suite in [("one", "OneTests"), ("two", "TwoTests")]
                    ]
                )
            )
            self.assertEqual([app.app_id for app in load_apps(source)], ["one", "two"])

    def test_registry_rejects_duplicate_and_unsafe_identities(self):
        app = {
            "id": "one",
            "title": "One",
            "testIdentifier": "OneTests/Export/capture()",
        }
        for rows in (
            [],
            [app, app],
            [{**app, "id": "../one"}],
            [{**app, "testIdentifier": "--all"}],
        ):
            with self.subTest(rows=rows), tempfile.TemporaryDirectory() as temporary:
                source = Path(temporary) / "apps.json"
                source.write_text(json.dumps(rows))
                with self.assertRaises(ValueError):
                    load_apps(source)

    def test_unknown_app_fails_before_capture(self):
        with self.assertRaisesRegex(ValueError, "Unknown"):
            load_app("missing")
