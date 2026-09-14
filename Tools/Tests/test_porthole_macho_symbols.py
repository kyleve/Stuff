"""Hermetic public-format parser regression fixtures."""
import struct
import tempfile
import unittest
from pathlib import Path
import sys

sys.path.insert(0,str(Path(__file__).resolve().parents[1]))
import porthole_macho_symbols as reader
from Fixtures.porthole_macho import thin, universal

class MachOReaderTests(unittest.TestCase):
    def read(self, data):
        with tempfile.TemporaryDirectory() as directory:
            path=Path(directory)/'image'
            path.write_bytes(data)
            return list(reader.external_definitions(path))

    def test_external_defined_filter_and_weak_bit(self):
        records = self.read(thin([
            ('_strong', 0x0F, 1, 0, None), ('_weak', 0x0F, 1, 0x80, None),
            ('_absolute', 0x03, 0, 0, None), ('_local', 0x0E, 1, 0, None),
            ('_undefined', 0x01, 0, 0, None), ('_debug', 0xEF, 1, 0, None),
            (None, 0x0F, 1, 0, None),
        ]))
        self.assertEqual([item.name for item in records], ['_strong','_weak','_absolute'])
        self.assertEqual([item.weak for item in records], [False,True,False])
        self.assertEqual(records[2].symbol_type, reader.N_ABS)

    def test_endian_and_universal_slice_relative_offsets(self):
        for child_endian in '<>':
            data=thin([('_value',0x0F,1,0,None)], endian=child_endian)
            self.assertEqual(self.read(data)[0].name, '_value')
            for container_endian in '<>':
                for fat64 in (False,True):
                    with self.subTest(child=child_endian,container=container_endian,fat64=fat64):
                        self.assertEqual(self.read(universal(data,container_endian,fat64))[0].name,'_value')

    def test_indirect_alias_retains_target(self):
        record=self.read(thin([('_alias',0x0B,0,0,'_target')]))[0]
        self.assertEqual(record.indirect_target,'_target')
        self.assertEqual(record.symbol_type, reader.N_INDR)

    def test_malformed_inputs_fail(self):
        valid=thin([('_value',0x0F,1,0,None)])
        cases=[]
        cases.extend([b'',valid[:31],valid[:-1]])
        changed=bytearray(valid);struct.pack_into('<I',changed,4,0x01000007);cases.append(changed)
        changed=bytearray(valid);struct.pack_into('<I',changed,36,7);cases.append(changed)
        changed=bytearray(valid);struct.pack_into('<I',changed,96,256);cases.append(changed)
        changed=bytearray(valid);struct.pack_into('<I',changed,192,0);cases.append(changed)
        changed=bytearray(valid);struct.pack_into('<I',changed,196,reader.MAX_SYMBOLS+1);cases.append(changed)
        changed=bytearray(valid);struct.pack_into('<I',changed,200,208);cases.append(changed)
        changed=bytearray(valid);struct.pack_into('<I',changed,204,reader.MAX_STRING_BYTES+1);cases.append(changed)
        changed=bytearray(valid);struct.pack_into('<I',changed,208,0xFFFFFFFF);cases.append(changed)
        changed=bytearray(valid);changed[213]=2;cases.append(changed)
        cases.append(thin([('_alias',0x0B,0,0,'')]))
        changed=bytearray(universal(valid));struct.pack_into('>I',changed,8,0x01000007);cases.append(changed)
        changed=bytearray(universal(valid));struct.pack_into('>I',changed,16,4097);cases.append(changed)
        changed=bytearray(universal(valid));struct.pack_into('<I',changed,4096+8,2);cases.append(changed)
        changed=bytearray(universal(valid,fat64=True));struct.pack_into('>I',changed,36,1);cases.append(changed)
        for index,data in enumerate(cases):
            with self.subTest(index=index),self.assertRaises(ValueError):self.read(data)

    def test_empty_symbol_table_is_valid(self):
        self.assertEqual(self.read(thin()),[])


if __name__=='__main__':unittest.main(verbosity=2)
