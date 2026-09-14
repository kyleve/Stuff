"""Read selected exports from the public Mach-O export trie without expanding it."""
from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path
import struct

from porthole_macho_symbols import CPU_TYPE_ARM64, MAX_COMMAND_BYTES, arm64_slice, read_exact

MAX_TRIE_BYTES = 64 * 1024 * 1024
MAX_EXPORT_NAME_BYTES = 4096
MAX_EXPORT_NAMES = 128


@dataclass(frozen=True)
class MachOExport:
    name: str
    flags: int
    value: int
    reexport: str | None
    resolver: int | None

    @property
    def weak(self):
        return bool(self.flags & 0x04)


def unsigned_leb(data, offset, end):
    value = 0
    for index in range(10):
        if offset >= end:
            raise ValueError('Truncated export trie ULEB128')
        byte = data[offset]
        offset += 1
        if index == 9 and byte > 1:
            raise ValueError('Export trie ULEB128 exceeds uint64')
        value |= (byte & 0x7F) << (7 * index)
        if not byte & 0x80:
            return value, offset
    raise ValueError('Export trie ULEB128 exceeds uint64')


def cstring(data, offset, end):
    terminator = data.find(b'\0', offset, min(end, offset + MAX_EXPORT_NAME_BYTES + 1))
    if terminator < 0:
        raise ValueError('Export trie string is unterminated or too long')
    return data[offset:terminator], terminator + 1


def lookup_export(data: bytes, name: str):
    wanted = name.encode('utf-8')
    if not wanted or len(wanted) > MAX_EXPORT_NAME_BYTES or b'\0' in wanted:
        raise ValueError('Invalid requested export name')
    offset = 0
    prefix = b''
    seen = set()
    while True:
        if offset in seen:
            raise ValueError('Cycle in selected export trie path')
        seen.add(offset)
        if len(seen) > len(wanted) + 1:
            raise ValueError('Export trie path exceeds name length')
        terminal_size, terminal_start = unsigned_leb(data, offset, len(data))
        terminal_end = terminal_start + terminal_size
        if terminal_end >= len(data):
            raise ValueError('Export trie terminal exceeds its buffer')
        # Validate selected terminal bodies even when the requested name continues.
        result = None
        if terminal_size:
            flags, position = unsigned_leb(data, terminal_start, terminal_end)
            if flags & ~0x3F or flags & 3 == 3:
                raise ValueError('Unknown export trie flags')
            value, position = unsigned_leb(data, position, terminal_end)
            reexport, resolver = None, None
            if flags & 0x08:
                if flags & 0x30 or flags & 3:
                    raise ValueError('Incompatible re-export flags')
                encoded, position = cstring(data, position, terminal_end)
                reexport = encoded.decode('utf-8')
            elif flags & 0x10:
                resolver, position = unsigned_leb(data, position, terminal_end)
            if position != terminal_end:
                raise ValueError('Unconsumed export trie terminal bytes')
            result = MachOExport(name, flags, value, reexport, resolver)
        children = data[terminal_end]
        position = terminal_end + 1
        match = None
        first_bytes = set()
        for _ in range(children):
            edge, position = cstring(data, position, len(data))
            if not edge or edge[0] in first_bytes:
                raise ValueError('Empty or ambiguous export trie edge')
            first_bytes.add(edge[0])
            child, position = unsigned_leb(data, position, len(data))
            if child >= len(data):
                raise ValueError('Export trie child is outside its buffer')
            next_prefix = prefix + edge
            if len(next_prefix) > MAX_EXPORT_NAME_BYTES:
                raise ValueError('Export trie name exceeds its limit')
            if wanted.startswith(next_prefix):
                match = next_prefix, child
        if prefix == wanted:
            return result
        if match is None:
            return None
        prefix, offset = match


def selected_exports(path: Path, names):
    requested = sorted(set(names))
    if len(requested) > MAX_EXPORT_NAMES:
        raise ValueError('Too many requested export names')
    with path.open('rb') as source:
        base, length, endian = arm64_slice(source, path.stat().st_size)
        end = base + length
        header = struct.unpack(endian+'IiiIIIII', read_exact(source, base, 32, base, end))
        _, cpu, _, filetype, count, command_bytes, _, _ = header
        if cpu != CPU_TYPE_ARM64 or filetype not in {1, 2, 6, 10}:
            raise ValueError('Unsupported Mach-O CPU or image type')
        if count > 4096 or command_bytes > MAX_COMMAND_BYTES or count*8 > command_bytes:
            raise ValueError('Invalid Mach-O load-command bounds')
        commands = read_exact(source, base+32, command_bytes, base, end)
        offset, export_range = 0, None
        mapped_ranges, image_bases = [], []
        for _ in range(count):
            if offset+8 > len(commands):
                raise ValueError('Truncated load command')
            command, size = struct.unpack_from(endian+'II', commands, offset)
            if size < 8 or size % 8 or size > len(commands)-offset:
                raise ValueError('Invalid load-command size')
            candidate = None
            if command == 0x19:
                if size < 72:
                    raise ValueError('Truncated LC_SEGMENT_64')
                _, _, _, vmaddr, vmsize, fileoff, filesize, _, protections, sections, _ = struct.unpack_from(endian+'II16sQQQQiiII', commands, offset)
                if size != 72+sections*80 or vmaddr+vmsize > 1 << 64:
                    raise ValueError('Invalid segment VM range or section table')
                if fileoff > length or filesize > length-fileoff:
                    raise ValueError('Segment file range exceeds Mach-O slice')
                if protections and vmsize:
                    mapped_ranges.append((vmaddr, vmaddr+vmsize))
                    if fileoff == 0 and filesize >= 32+command_bytes:
                        image_bases.append(vmaddr)
            elif command == 0x80000033:
                if size != 16:
                    raise ValueError('Invalid LC_DYLD_EXPORTS_TRIE size')
                candidate = struct.unpack_from(endian+'II', commands, offset+8)
            elif command in {0x22, 0x80000022}:
                if size != 48:
                    raise ValueError('Invalid LC_DYLD_INFO size')
                candidate = struct.unpack_from(endian+'II', commands, offset+40)
            if candidate is not None and candidate[1]:
                if export_range is not None:
                    raise ValueError('Multiple nonempty Mach-O export tries')
                export_range = candidate
            offset += size
        if offset != command_bytes:
            raise ValueError('Unconsumed load commands')
        if export_range is None:
            return []
        file_offset, size = export_range
        if size > MAX_TRIE_BYTES or file_offset < 32+command_bytes:
            raise ValueError('Invalid export trie bounds')
        data = read_exact(source, base+file_offset, size, base, end)
    results = [result for name in requested if (result := lookup_export(data, name)) is not None]
    if len(image_bases) != 1:
        raise ValueError('Expected one mapped Mach-O header segment')
    for result in results:
        if result.flags & 0x03 == 0 and not result.flags & 0x08:
            address = image_bases[0]+result.value
            if address >= 1 << 64 or not any(start <= address < end for start, end in mapped_ranges):
                raise ValueError('Selected regular export is outside mapped segments')
    return results
