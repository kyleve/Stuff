"""Bounded arm64 Mach-O symbol reader using public mach-o/loader.h and nlist.h layouts."""
from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path
import struct

CPU_TYPE_ARM64 = 0x0100000C
N_STAB, N_EXT, N_TYPE, N_WEAK_DEF = 0xE0, 0x01, 0x0E, 0x0080
N_ABS, N_INDR, N_SECT = 0x02, 0x0A, 0x0E
MAX_COMMAND_BYTES = 8 * 1024 * 1024
MAX_SYMBOLS = 2_000_000
MAX_STRING_BYTES = 256 * 1024 * 1024
MAX_NAME_BYTES = 1024 * 1024


@dataclass(frozen=True)
class MachOSymbol:
    name: str
    value: int
    symbol_type: int
    section: int
    description: int
    indirect_target: str | None

    @property
    def weak(self):
        return bool(self.description & N_WEAK_DEF)


def read_exact(source, offset, length, lower, upper):
    if offset < lower or length < 0 or offset > upper or length > upper - offset:
        raise ValueError('Mach-O read is outside the selected file/slice')
    source.seek(offset)
    result = source.read(length)
    if len(result) != length:
        raise ValueError('Truncated Mach-O input')
    return result


def arm64_slice(source, size):
    magic = read_exact(source, 0, 4, 0, size)
    thin = {b'\xcf\xfa\xed\xfe':'<', b'\xfe\xed\xfa\xcf':'>'}
    if magic in thin:
        return 0, size, thin[magic]
    fat = {b'\xca\xfe\xba\xbe':('>',False), b'\xbe\xba\xfe\xca':('<',False),
           b'\xca\xfe\xba\xbf':('>',True), b'\xbf\xba\xfe\xca':('<',True)}
    if magic not in fat:
        raise ValueError('Expected a 64-bit Mach-O or universal container')
    endian, fat64 = fat[magic]
    count = struct.unpack(endian+'I',read_exact(source,4,4,0,size))[0]
    if not 1 <= count <= 16:
        raise ValueError('Unsupported universal architecture count')
    entry_size = 32 if fat64 else 20
    table_end = 8 + count * entry_size
    entries = read_exact(source,8,count*entry_size,0,size)
    slices = []
    selected = []
    for index in range(count):
        fields = struct.unpack_from(endian+('iiQQII' if fat64 else 'iiIII'), entries, index*entry_size)
        cpu, subtype, offset, length, alignment = fields[:5]
        if fat64 and fields[5] != 0:
            raise ValueError('Nonzero universal architecture reserved field')
        if alignment > 32 or offset < table_end or length < 32 or offset > size or length > size-offset:
            raise ValueError('Invalid universal slice range')
        if offset % (1 << alignment):
            raise ValueError('Misaligned universal slice')
        if any(offset < end and start < offset+length for start,end in slices):
            raise ValueError('Overlapping universal slices')
        slices.append((offset,offset+length))
        if cpu == CPU_TYPE_ARM64:
            child_magic = read_exact(source,offset,4,offset,offset+length)
            if child_magic not in thin:
                raise ValueError('arm64 slice is not a 64-bit Mach-O')
            child_endian = thin[child_magic]
            child_cpu, child_subtype = struct.unpack(child_endian+'ii', read_exact(source,offset+4,8,offset,offset+length))
            if (child_cpu, child_subtype) != (cpu, subtype):
                raise ValueError('Universal and Mach-O CPU identities differ')
            selected.append((offset,length,child_endian))
    if len(selected) != 1:
        raise ValueError('Expected exactly one arm64 slice')
    return selected[0]


def external_definitions(path: Path):
    """Yield external definitions, including their weak bit and explicit indirect target."""
    with path.open('rb') as source:
        base,length,endian = arm64_slice(source,path.stat().st_size)
        end = base+length
        header = struct.unpack(endian+'IiiIIIII',read_exact(source,base,32,base,end))
        _,cpu,_,filetype,count,command_bytes,_,_ = header
        if cpu != CPU_TYPE_ARM64 or filetype not in {1,2,6,10}:
            raise ValueError('Unsupported Mach-O CPU or image type')
        if count > 4096 or command_bytes > MAX_COMMAND_BYTES or count*8 > command_bytes:
            raise ValueError('Invalid Mach-O load-command bounds')
        commands = read_exact(source,base+32,command_bytes,base,end)
        offset,sections = 0,0
        symtab = None
        for _ in range(count):
            if offset+8 > len(commands):
                raise ValueError('Truncated load command')
            command,command_size = struct.unpack_from(endian+'II',commands,offset)
            if command_size < 8 or command_size % 8 or command_size > len(commands)-offset:
                raise ValueError('Invalid load-command size')
            if command == 0x19:
                if command_size < 72:
                    raise ValueError('Truncated LC_SEGMENT_64')
                section_count = struct.unpack_from(endian+'I',commands,offset+64)[0]
                if command_size != 72+section_count*80:
                    raise ValueError('Invalid segment section table')
                sections += section_count
                if sections > 255:
                    raise ValueError('Section count exceeds n_sect representation')
            elif command == 2:
                if command_size != 24 or symtab is not None:
                    raise ValueError('Invalid or duplicate LC_SYMTAB')
                symtab = struct.unpack_from(endian+'IIII',commands,offset+8)
            offset += command_size
        if offset != command_bytes or symtab is None:
            raise ValueError('Missing symbol table or unconsumed load commands')
        symbol_offset,symbol_count,string_offset,string_size = symtab
        if symbol_count > MAX_SYMBOLS or string_size > MAX_STRING_BYTES:
            raise ValueError('Symbol or string table exceeds inspection limits')
        table_start = 32+command_bytes
        if symbol_offset < table_start or string_offset < table_start:
            raise ValueError('Symbol table overlaps Mach-O load commands')
        if symbol_count*16 and string_size and symbol_offset < string_offset+string_size and string_offset < symbol_offset+symbol_count*16:
            raise ValueError('Symbol and string tables overlap')
        table = read_exact(source,base+symbol_offset,symbol_count*16,base,end)
        strings = read_exact(source,base+string_offset,string_size,base,end)

        def name_at(index):
            if index == 0:
                return ''
            if index >= len(strings):
                raise ValueError('Symbol string index is outside LC_SYMTAB')
            terminator = strings.find(b'\0',index,min(len(strings),index+MAX_NAME_BYTES+1))
            if terminator < 0:
                raise ValueError('Symbol name is unterminated or exceeds its limit')
            return strings[index:terminator].decode('utf-8')

        for string_index,kind,section,description,value in struct.iter_unpack(endian+'IBBHQ',table):
            if kind & N_STAB or not kind & N_EXT:
                continue
            symbol_type = kind & N_TYPE
            if symbol_type not in {N_ABS,N_INDR,N_SECT}:
                continue
            if symbol_type == N_SECT and not 1 <= section <= sections:
                raise ValueError('Defined symbol has an invalid section ordinal')
            name = name_at(string_index)
            if not name:
                continue
            target = name_at(value) if symbol_type == N_INDR else None
            if target == '':
                raise ValueError('Indirect symbol has an empty target')
            yield MachOSymbol(name,value,symbol_type,section,description,target)
