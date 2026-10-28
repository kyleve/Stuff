from pathlib import Path
import struct
import os
import tempfile
import unittest
from unittest.mock import patch
import zlib

from Tools.flyover_png import validate_png
from Tools.Tests.flyover_test_support import png_fixture


def chunk(kind, data):
    return (
        struct.pack(">I", len(data))
        + kind
        + data
        + struct.pack(">I", zlib.crc32(kind + data))
    )


class FlyoverPNGTests(unittest.TestCase):
    def test_links_and_special_files_are_rejected_without_blocking(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            source = root / "capture.png"
            source.write_bytes(png_fixture(3, 3))
            link = root / "link.png"
            link.symlink_to(source)
            fifo = root / "fifo.png"
            os.mkfifo(fifo)
            for path in (link, fifo, root):
                with self.subTest(path=path), self.assertRaises(ValueError):
                    validate_png(path, 3, 3)

    def test_unsupported_encodings_and_split_data_fail(self):
        image = png_fixture(3, 3)
        header = struct.pack(">IIBBBBB", 3, 3, 8, 3, 0, 0, 0)
        unsupported = image[:8] + chunk(b"IHDR", header) + image[33:]
        split = (
            image[:-12]
            + chunk(b"tEXt", b"note\x00value")
            + chunk(b"IDAT", b"")
            + chunk(b"IEND", b"")
        )
        for data in (unsupported, split):
            with tempfile.TemporaryDirectory() as directory:
                path = Path(directory) / "capture.png"
                path.write_bytes(data)
                with self.assertRaises(ValueError):
                    validate_png(path, 3, 3)

    def test_valid_capture_and_dimension_mismatch(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "capture.png"
            path.write_bytes(png_fixture(3, 3))
            validate_png(path, 3, 3)
            with self.assertRaisesRegex(ValueError, "dimensions"):
                validate_png(path, 4, 3)

    def test_truncation_crc_trailing_bytes_and_invalid_filter_fail(self):
        image = png_fixture(3, 3)
        bad_filter = (
            image[:33]
            + chunk(b"IDAT", zlib.compress(b"\x05abc" * 3))
            + chunk(b"IEND", b"")
        )
        for data in (
            b"PNG",
            image[:-1],
            image[:45] + bytes([image[45] ^ 1]) + image[46:],
            image + b"extra",
            bad_filter,
        ):
            with self.subTest(data=data), tempfile.TemporaryDirectory() as directory:
                path = Path(directory) / "capture.png"
                path.write_bytes(data)
                with self.assertRaises(ValueError):
                    validate_png(path, 3, 3)

    def test_expansion_and_encoded_size_limits_fail(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "capture.png"
            path.write_bytes(png_fixture(3, 3))
            for limit in ("MAX_FILE_BYTES", "MAX_DECODED_BYTES"):
                with (
                    patch("Tools.flyover_png." + limit, 1),
                    self.assertRaises(ValueError),
                ):
                    validate_png(path, 3, 3)

    def test_extra_inflated_data_and_incomplete_stream_fail(self):
        for raw in (b"\x00abc" * 4, b"\x00abc" * 2):
            with tempfile.TemporaryDirectory() as directory:
                path = Path(directory) / "capture.png"
                path.write_bytes(
                    png_fixture(3, 3)[:33]
                    + chunk(b"IDAT", zlib.compress(raw))
                    + chunk(b"IEND", b"")
                )
                with self.assertRaises(ValueError):
                    validate_png(path, 3, 3)
