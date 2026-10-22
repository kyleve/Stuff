import importlib.util
import os
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

try:
    from Tools.Tests.flyover_test_support import create_flyover_artifact
except ModuleNotFoundError as error:
    if error.name != "Tools":
        raise
    from flyover_test_support import create_flyover_artifact


MODULE_PATH = Path(__file__).resolve().parents[1] / "flyover_preview.py"
SPEC = importlib.util.spec_from_file_location("flyover_preview", MODULE_PATH)
flyover_preview = importlib.util.module_from_spec(SPEC)
assert SPEC.loader
sys.modules[SPEC.name] = flyover_preview
SPEC.loader.exec_module(flyover_preview)


class FlyoverPreviewTests(unittest.TestCase):
    fixture = staticmethod(create_flyover_artifact)

    def test_replacement_fifo_is_rejected_without_waiting_for_a_writer(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = self.fixture(Path(temporary))
            artifact = flyover_preview.validate_artifact(root)
            relative = "images/screen-0001/variant-0001/phone-light.png"
            image = root / relative
            with flyover_preview._open_artifact_root(artifact) as descriptor:
                image.unlink()
                os.mkfifo(image)
                # Isolate a blocking regression so the suite can terminate it.
                result = subprocess.run(
                    [sys.executable, "-c", """
import sys
from Tools.flyover_preview import _open_file_beneath
try:
    with _open_file_beneath(int(sys.argv[1]), sys.argv[2]):
        raise AssertionError("preview accepted a FIFO")
except OSError:
    pass
""", str(descriptor), relative],
                    cwd=MODULE_PATH.parent.parent,
                    pass_fds=(descriptor,),
                    capture_output=True,
                    text=True,
                    timeout=5,
                )
                self.assertEqual(result.returncode, 0, result.stderr)

    def test_opening_an_allowlisted_file_does_not_follow_a_replacement_symlink(self):
        with tempfile.TemporaryDirectory() as temporary:
            temporary_root = Path(temporary)
            root = self.fixture(temporary_root / "atlas")
            artifact = flyover_preview.validate_artifact(root)
            image = root / "images/screen-0001/variant-0001/phone-light.png"
            outside = temporary_root / "outside"
            outside.write_bytes(b"SECRET")

            with flyover_preview._open_artifact_root(artifact) as descriptor:
                image.unlink()
                image.symlink_to(outside)
                with self.assertRaises(OSError):
                    flyover_preview._open_file_beneath(
                        descriptor,
                        "images/screen-0001/variant-0001/phone-light.png",
                    )

    def test_server_root_descriptor_stays_on_the_validated_directory(self):
        with tempfile.TemporaryDirectory() as temporary:
            temporary_root = Path(temporary)
            root = self.fixture(temporary_root / "atlas")
            artifact = flyover_preview.validate_artifact(root)
            moved = temporary_root / "validated-atlas"

            with flyover_preview._open_artifact_root(artifact) as descriptor:
                root.rename(moved)
                root.mkdir()
                (root / "manifest.json").write_bytes(b"SECRET")
                with flyover_preview._open_file_beneath(
                    descriptor,
                    "manifest.json",
                ) as manifest_file:
                    self.assertIn(b'"schemaVersion": 1', manifest_file.read())
