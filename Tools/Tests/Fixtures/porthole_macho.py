"""Synthetic Mach-O records for parser and packaging tests; never compile or load them."""
import struct
import porthole_macho_symbols as reader

def thin(symbols=None, endian='<', cpu=reader.CPU_TYPE_ARM64):
    # One valid segment containing one section; all symbol offsets are slice-relative.
    strings = bytearray(b'not-a-symbol\0')
    records = []
    for name, kind, section, description, target in symbols or []:
        index = len(strings) if name is not None else 0
        if name is not None:
            strings.extend(name.encode() + b'\0')
        value = 0x1000
        if target is not None:
            value = len(strings)
            strings.extend(target.encode() + b'\0')
        records.append(struct.pack(endian+'IBBHQ', index, kind, section, description, value))
    segment = bytearray(152)
    struct.pack_into(endian+'II', segment, 0, 0x19, len(segment))
    struct.pack_into(endian+'I', segment, 64, 1)
    symbol_offset = 32 + len(segment) + 24
    table = b''.join(records)
    command = struct.pack(endian+'IIIIII', 2, 24, symbol_offset, len(records), symbol_offset+len(table), len(strings))
    header = struct.pack(endian+'IiiIIIII', 0xFEEDFACF, cpu, 0, 6, 2, len(segment)+len(command), 0, 0)
    return header + segment + command + table + strings


def universal(payload, endian='>', fat64=False):
    offset = 4096
    prefix = struct.pack(endian+'II', 0xCAFEBABF if fat64 else 0xCAFEBABE, 1)
    if fat64:
        entry = struct.pack(endian+'iiQQII', reader.CPU_TYPE_ARM64, 0, offset, len(payload), 12, 0)
    else:
        entry = struct.pack(endian+'iiIII', reader.CPU_TYPE_ARM64, 0, offset, len(payload), 12)
    return (prefix+entry).ljust(offset, b'\0')+payload


def uleb(value):
    output=bytearray()
    while True:
        byte=value&127;value>>=7;output.append(byte|(128 if value else 0))
        if not value:return bytes(output)


def leaf(name='_value', flags=0, value=0x200, extra=b''):
    terminal=uleb(flags)+uleb(value)+extra
    node=uleb(len(terminal))+terminal+b'\0'
    edge=name.encode()+b'\0'
    offset=2+len(edge)+1
    return b'\0\1'+edge+uleb(offset)+node


def image(trie, endian='<', legacy=False):
    command_size=48 if legacy else 16
    start=32+72+command_size
    segment=struct.pack(endian+'II16sQQQQiiII',0x19,72,b'__TEXT',0x100000000,0x1000,0,start+len(trie),5,5,0,0)
    if legacy:
        command=struct.pack(endian+'IIIIIIIIIIII',0x80000022,48,0,0,0,0,0,0,0,0,start,len(trie))
    else:
        command=struct.pack(endian+'IIII',0x80000033,16,start,len(trie))
    header=struct.pack(endian+'IiiIIIII',0xFEEDFACF,0x0100000C,0,6,2,72+command_size,0,0)
    return header+segment+command+trie
