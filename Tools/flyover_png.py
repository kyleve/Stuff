"""Bounded validation of native, non-interlaced RGB/gray PNG captures.

Validate every chunk CRC, the complete zlib stream, scanline filters, and dimensions.
Reject other encodings explicitly rather than accepting an unvalidated image.
"""

from pathlib import Path
import os
import stat
import struct
import zlib

from Tools.flyover_schema_values import FlyoverArtifactError


MAX_FILE_BYTES = 128 * 1024 * 1024
MAX_DECODED_BYTES = 512 * 1024 * 1024


def validate_png(path: Path, width: int, height: int) -> None:
    try:
        _validate(path, width, height)
    except (OSError, ValueError, zlib.error, struct.error) as error:
        raise FlyoverArtifactError(f"invalid PNG {path.name}: {error}") from error


def _validate(path: Path, width: int, height: int) -> None:
    descriptor = os.open(path, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK)
    with os.fdopen(descriptor, 'rb') as source:
        status = os.fstat(source.fileno())
        if not stat.S_ISREG(status.st_mode) or status.st_size > MAX_FILE_BYTES:
            raise ValueError("image is not a bounded regular file")
        def read(count):
            data = source.read(count)
            if len(data) != count:
                raise ValueError("truncated image")
            return data

        if read(8) != b'\x89PNG\r\n\x1a\n':
            raise ValueError("missing PNG signature")
        decoder = zlib.decompressobj()
        row_bytes = None
        expected = 0
        decoded = 0
        saw_data = False
        data_ended = False
        while True:
            length, kind = struct.unpack('>I4s', read(8))
            if length > MAX_FILE_BYTES:
                raise ValueError("chunk exceeds the size limit")
            payload = read(length)
            checksum = struct.unpack('>I', read(4))[0]
            if zlib.crc32(payload, zlib.crc32(kind)) != checksum:
                raise ValueError("chunk checksum mismatch")
            if row_bytes is None and kind != b'IHDR':
                raise ValueError("missing image header")
            if kind == b'IHDR':
                if row_bytes is not None or length != 13:
                    raise ValueError("invalid image header")
                actual_width, actual_height, depth, color, compression, filtering, interlace = struct.unpack('>IIBBBBB', payload)
                if (actual_width, actual_height) != (width, height) or width <= 0 or height <= 0:
                    raise ValueError("pixel dimensions differ from the manifest")
                channels = {0: 1, 2: 3, 4: 2, 6: 4}.get(color)
                if channels is None or depth not in (8, 16) or (compression, filtering, interlace) != (0, 0, 0):
                    raise ValueError("unsupported native capture encoding")
                row_bytes = 1 + width * channels * (depth // 8)
                expected = row_bytes * height
                if expected > MAX_DECODED_BYTES:
                    raise ValueError("decoded image exceeds the size limit")
            elif kind == b'IDAT':
                if data_ended:
                    raise ValueError("non-consecutive image data")
                saw_data = True
                pending = payload
                while pending:
                    block = decoder.decompress(pending, min(64 * 1024, expected - decoded + 1))
                    # A native scanline starts with one of PNG's five filter methods.
                    for offset in range((-decoded) % row_bytes, len(block), row_bytes):
                        if block[offset] > 4:
                            raise ValueError("invalid scanline filter")
                    decoded += len(block)
                    if decoded > expected or decoder.unused_data:
                        raise ValueError("extra image data")
                    pending = decoder.unconsumed_tail
            elif kind == b'IEND':
                if length or not saw_data or not decoder.eof or decoded != expected or source.read(1):
                    raise ValueError("incomplete or trailing image data")
                return
            else:
                if saw_data:
                    data_ended = True
                if kind == b'PLTE':
                    if saw_data or not 0 < length <= 768 or length % 3:
                        raise ValueError("invalid palette")
                elif not kind[0] & 32:
                    raise ValueError("unsupported critical chunk")
