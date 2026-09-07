import importlib.util
import io
import json
import signal
import sys
import tempfile
import threading
import unittest
from pathlib import Path


MODULE_PATH = Path(__file__).resolve().parents[1] / "flyover_preview.py"
SPEC = importlib.util.spec_from_file_location("flyover_preview", MODULE_PATH)
flyover_preview = importlib.util.module_from_spec(SPEC)
assert SPEC.loader
sys.modules[SPEC.name] = flyover_preview
SPEC.loader.exec_module(flyover_preview)


class FlyoverPreviewTests(unittest.TestCase):
    def write_manifest(self, root: Path, manifest: object) -> None:
        data = json.dumps(manifest)
        (root / "manifest.json").write_text(data)
        (root / "manifest.js").write_text(
            "window.FLYOVER_MANIFEST = " + data + ";\n"
        )

    def fixture(self, root: Path) -> Path:
        (root / "assets").mkdir(parents=True)
        image = root / "images/screen-0001/variant-0001/phone-light.png"
        image.parent.mkdir(parents=True)
        image.write_bytes(b"PNG")
        (root / ".flyover-generated").write_text("schemaVersion=1\n")
        (root / "index.html").write_text("<!doctype html>")
        (root / "assets/app.js").write_text("")
        (root / "assets/styles.css").write_text("")
        self.write_manifest(
            root,
            {
                "schemaVersion": 1,
                "images": [
                    {
                        "relativePath": (
                            "images/screen-0001/variant-0001/phone-light.png"
                        )
                    }
                ],
            },
        )
        return root

    def test_validates_generated_artifact_and_builds_allowlist(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = self.fixture(Path(temporary))

            artifact = flyover_preview.validate_artifact(root)

            self.assertEqual(artifact.root, root)
            self.assertEqual(
                artifact.allowed_paths,
                frozenset(
                    {
                        "index.html",
                        "manifest.json",
                        "manifest.js",
                        "assets/app.js",
                        "assets/styles.css",
                        "images/screen-0001/variant-0001/phone-light.png",
                    }
                ),
            )

    def test_rejects_invalid_marker_and_symbolic_links(self):
        with tempfile.TemporaryDirectory() as temporary:
            temporary_root = Path(temporary)
            root = self.fixture(temporary_root / "atlas")
            (root / ".flyover-generated").write_text("schemaVersion=2\n")
            with self.assertRaisesRegex(
                flyover_preview.FlyoverArtifactError,
                "generated marker is unsupported",
            ):
                flyover_preview.validate_artifact(root)

            (root / ".flyover-generated").write_bytes(b"\xff")
            with self.assertRaisesRegex(
                flyover_preview.FlyoverArtifactError,
                "could not read",
            ):
                flyover_preview.validate_artifact(root)

            (root / ".flyover-generated").write_text("schemaVersion=1\n")
            (root / "leak").symlink_to(temporary_root / "outside")
            with self.assertRaisesRegex(
                flyover_preview.FlyoverArtifactError,
                "contains a symbolic link",
            ):
                flyover_preview.validate_artifact(root)

    def test_rejects_unsafe_missing_duplicate_and_extra_images(self):
        scenarios = (
            ("../outside.png", "unsafe image path"),
            ("/outside.png", "unsafe image path"),
            ("images/missing.png", "manifest image is missing"),
        )
        for relative_path, message in scenarios:
            with self.subTest(relative_path=relative_path):
                with tempfile.TemporaryDirectory() as temporary:
                    root = self.fixture(Path(temporary))
                    manifest_path = root / "manifest.json"
                    manifest = json.loads(manifest_path.read_text())
                    manifest["images"][0]["relativePath"] = relative_path
                    self.write_manifest(root, manifest)
                    with self.assertRaisesRegex(
                        flyover_preview.FlyoverArtifactError,
                        message,
                    ):
                        flyover_preview.validate_artifact(root)

        with tempfile.TemporaryDirectory() as temporary:
            root = self.fixture(Path(temporary))
            manifest_path = root / "manifest.json"
            manifest = json.loads(manifest_path.read_text())
            manifest["images"].append(dict(manifest["images"][0]))
            self.write_manifest(root, manifest)
            with self.assertRaisesRegex(
                flyover_preview.FlyoverArtifactError,
                "duplicate image path",
            ):
                flyover_preview.validate_artifact(root)

        with tempfile.TemporaryDirectory() as temporary:
            root = self.fixture(Path(temporary))
            (root / "images/extra.png").write_bytes(b"PNG")
            with self.assertRaisesRegex(
                flyover_preview.FlyoverArtifactError,
                "image files do not match",
            ):
                flyover_preview.validate_artifact(root)

    def test_rejects_non_object_boolean_schema_and_mismatched_script(self):
        scenarios = (
            ([], "not a JSON object"),
            ({"schemaVersion": True, "images": []}, "schemaVersion 1"),
        )
        for manifest, message in scenarios:
            with self.subTest(manifest=manifest):
                with tempfile.TemporaryDirectory() as temporary:
                    root = self.fixture(Path(temporary))
                    self.write_manifest(root, manifest)
                    with self.assertRaisesRegex(
                        flyover_preview.FlyoverArtifactError,
                        message,
                    ):
                        flyover_preview.validate_artifact(root)

        with tempfile.TemporaryDirectory() as temporary:
            root = self.fixture(Path(temporary))
            (root / "manifest.js").write_text("window.FLYOVER_MANIFEST = {};\n")
            with self.assertRaisesRegex(
                flyover_preview.FlyoverArtifactError,
                "manifest.js does not match manifest.json",
            ):
                flyover_preview.validate_artifact(root)

    def test_filters_and_sorts_usable_ipv4_addresses(self):
        self.assertEqual(
            flyover_preview.usable_ipv4_addresses(
                (
                    "192.168.1.20",
                    "127.0.0.1",
                    "0.0.0.0",
                    "224.0.0.1",
                    "169.254.2.3",
                    "10.0.0.7",
                    "192.168.1.20",
                    "::1",
                    "invalid",
                )
            ),
            ("10.0.0.7", "169.254.2.3", "192.168.1.20"),
        )

    def test_serves_loopback_on_an_automatic_port(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = self.fixture(Path(temporary))
            servers = []

            class FakeServer:
                def __init__(self, address, handler):
                    self.address = address
                    self.handler = handler
                    self.server_address = (address[0], 53142)
                    self.did_serve = False
                    servers.append(self)

                def __enter__(self):
                    return self

                def __exit__(self, *_):
                    return None

                def serve_forever(self):
                    self.did_serve = True

            output = io.StringIO()
            flyover_preview.serve(
                root,
                lan=False,
                port=0,
                output=output,
                server_factory=FakeServer,
            )

            self.assertEqual(servers[0].address, ("127.0.0.1", 0))
            self.assertTrue(servers[0].did_serve)
            self.assertEqual(
                output.getvalue().splitlines(),
                [
                    f"Flyover preview: {root}",
                    "Local:   http://127.0.0.1:53142/",
                    "Press Ctrl-C to stop.",
                ],
            )

    def test_ctrl_c_stops_preview_and_restores_signal_handler(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = self.fixture(Path(temporary))
            shutdown_called = threading.Event()
            servers = []

            class InterruptingOutput(io.StringIO):
                def __init__(self):
                    super().__init__()
                    self.did_interrupt = False

                def flush(self):
                    super().flush()
                    if not self.did_interrupt:
                        self.did_interrupt = True
                        signal.raise_signal(signal.SIGINT)

            class FakeServer:
                server_address = ("127.0.0.1", 53142)

                def __init__(self, *_):
                    self.serving_thread = None
                    self.shutdown_thread = None
                    servers.append(self)

                def __enter__(self):
                    return self

                def __exit__(self, *_):
                    return None

                def serve_forever(self):
                    self.serving_thread = threading.current_thread()
                    if not shutdown_called.wait(timeout=5):
                        raise AssertionError("preview shutdown was not requested")

                def shutdown(self):
                    self.shutdown_thread = threading.current_thread()
                    shutdown_called.set()

            previous_handler = signal.getsignal(signal.SIGINT)

            flyover_preview.serve(
                root,
                lan=False,
                port=0,
                output=InterruptingOutput(),
                server_factory=FakeServer,
            )

            self.assertTrue(shutdown_called.is_set())
            self.assertIsNot(servers[0].serving_thread, servers[0].shutdown_thread)
            self.assertEqual(signal.getsignal(signal.SIGINT), previous_handler)

    def test_server_failure_is_rethrown_and_restores_signal_handler(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = self.fixture(Path(temporary))

            class FakeServer:
                server_address = ("127.0.0.1", 53142)

                def __init__(self, *_):
                    pass

                def __enter__(self):
                    return self

                def __exit__(self, *_):
                    return None

                def serve_forever(self):
                    raise RuntimeError("server failed")

            previous_handler = signal.getsignal(signal.SIGINT)

            with self.assertRaisesRegex(RuntimeError, "server failed"):
                flyover_preview.serve(
                    root,
                    lan=False,
                    port=0,
                    output=io.StringIO(),
                    server_factory=FakeServer,
                )

            self.assertEqual(signal.getsignal(signal.SIGINT), previous_handler)

    def test_lan_preview_prints_each_network_url_and_warning(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = self.fixture(Path(temporary))
            addresses = []

            class FakeServer:
                server_address = ("0.0.0.0", 8080)

                def __init__(self, address, _):
                    addresses.append(address)

                def __enter__(self):
                    return self

                def __exit__(self, *_):
                    return None

                def serve_forever(self):
                    return None

            output = io.StringIO()
            flyover_preview.serve(
                root,
                lan=True,
                port=8080,
                output=output,
                server_factory=FakeServer,
                address_provider=lambda: ("10.0.0.7", "192.168.1.20"),
            )

            self.assertEqual(addresses, [("0.0.0.0", 8080)])
            self.assertIn("Network: http://10.0.0.7:8080/", output.getvalue())
            self.assertIn("Network: http://192.168.1.20:8080/", output.getvalue())
            self.assertIn(
                "Warning: LAN preview has no authentication or TLS.",
                output.getvalue(),
            )

    def test_reports_bind_errors_without_starting_the_server(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = self.fixture(Path(temporary))

            def failed_server(*_):
                raise OSError("address already in use")

            with self.assertRaisesRegex(
                flyover_preview.FlyoverArtifactError,
                "could not start the preview server.*address already in use",
            ):
                flyover_preview.serve(
                    root,
                    lan=False,
                    port=4173,
                    server_factory=failed_server,
                )


if __name__ == "__main__":
    unittest.main()
