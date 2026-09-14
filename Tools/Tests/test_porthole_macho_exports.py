"""Hermetic public-format parser regression fixtures."""
import struct
import tempfile
import unittest
from pathlib import Path
import sys

sys.path.insert(0,str(Path(__file__).resolve().parents[1]))
import porthole_macho_exports as reader
from Fixtures.porthole_macho import leaf, image, universal, uleb

class MachOExportTests(unittest.TestCase):
    def read(self, data, names=('_value',)):
        with tempfile.TemporaryDirectory() as directory:
            path=Path(directory)/'image';path.write_bytes(data)
            return reader.selected_exports(path,names)

    def test_direct_export_and_weak_flags(self):
        for flag in (0,4):
            r=self.read(image(leaf(flags=flag)))[0]
            self.assertEqual((r.name,r.value,r.weak),('_value',0x200,bool(flag)))
        self.assertEqual(self.read(image(leaf()),['_absent']),[])

    def test_old_new_commands_endian_and_universal_offsets(self):
        for endian in '<>':
            for legacy in (False,True):
                data=image(leaf(),endian,legacy)
                self.assertEqual(self.read(data)[0].value,0x200)
                self.assertEqual(self.read(universal(data))[0].value,0x200)

    def test_reexport_and_resolver_remain_distinct(self):
        alias=self.read(image(leaf(flags=8,value=1,extra=b'_elsewhere\0')))[0]
        self.assertEqual((alias.value,alias.reexport),(1,'_elsewhere'))
        resolver=self.read(image(leaf(flags=16,extra=uleb(0x300))))[0]
        self.assertEqual(resolver.resolver,0x300)

    def test_malformed_uleb_nodes_edges_and_addresses(self):
        self.assertEqual(self.read(image(b'')),[])
        cases=[b'\x80'*11,b'\x01',b'\0\1abc',b'\0\1_value\0\x7f',b'\0\1_value\0\0',
               b'\0\1\0\0',b'\0\2a\0\0a\0\0',leaf(flags=64),leaf(flags=3),leaf(extra=b'extra'),
               leaf(value=0x1000),leaf(value=(1<<64)-1),leaf(flags=8,value=1,extra=b'unterminated')]
        for index,trie in enumerate(cases):
            with self.subTest(index=index),self.assertRaises(ValueError):self.read(image(trie))
        data=bytearray(image(leaf()));struct.pack_into('<I',data,112,0)
        with self.assertRaises(ValueError):self.read(data)
        data=bytearray(image(leaf()));struct.pack_into('<I',data,116,reader.MAX_TRIE_BYTES+1)
        with self.assertRaises(ValueError):self.read(data)
        data=bytearray(image(leaf()));struct.pack_into('<I',data,92,0)
        with self.assertRaises(ValueError):self.read(data)


if __name__=='__main__':unittest.main(verbosity=2)
