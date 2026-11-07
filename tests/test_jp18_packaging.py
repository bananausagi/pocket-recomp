"""ROM-free regressions for the Lua-only Android release contract."""
import importlib.util
import io
import json
import struct
import sys
import tempfile
import unittest
import zipfile
from pathlib import Path

ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/'tools'))
import repack_jp_android as repack
import audit_jp_release as audit

class PackagingTests(unittest.TestCase):
    def test_lua_only_java_sources_pinned(self):
        self.assertEqual(len(repack.verify_native_sources()),138)

    def test_modified_or_added_java_source_rejected(self):
        previous=repack.ROOT
        try:
            with tempfile.TemporaryDirectory() as tmp:
                root=Path(tmp);(root/'tools').mkdir();(root/'mobile/android').mkdir(parents=True)
                (root/'tools/jp19_native_baseline.json').write_text(json.dumps({'mode':'lua-only','base_sha256':repack.BASE_SHA256,'java_source_sha256':{},'mod_source_sha256':{},'allowed_mod_source_changes':['vendor/jp-mods/running_shoes/'+n for n in ('JP-ADAPTATION.md','main.lua','manifest.json','tests/running_shoes_test.lua')]}))
                repack.ROOT=root
                self.assertEqual(repack.verify_native_sources(),{})
                (root/'mobile/android/Unexpected.java').write_text('class Unexpected {}')
                with self.assertRaises(AssertionError):repack.verify_native_sources()
                (root/'mobile/android/Unexpected.java').unlink()
                (root/'vendor/jp-mods').mkdir(parents=True)
                (root/'vendor/jp-mods/Unexpected.lua').write_text('return {}')
                with self.assertRaises(AssertionError):repack.verify_native_sources()
        finally:repack.ROOT=previous

    def test_private_and_rom_files_rejected(self):
        for name in ('copy.gb','save.sav','signing.keystore','nested/key.jks','data/generated/red_jp/font.lua','assets/logo/old.png'):
            with self.subTest(name=name),self.assertRaises(AssertionError):audit.inspect(b'synthetic',name,{'scanned_files':0})
        data=bytearray(0x200);data[0x104:0x134]=audit.GB_HEADER
        with self.assertRaises(AssertionError):audit.inspect(bytes(data),'disguised.bin',{'scanned_files':0})

    def test_nested_archive_scanned(self):
        b=io.BytesIO()
        with zipfile.ZipFile(b,'w') as z:z.writestr('private.sav',b'synthetic')
        with self.assertRaises(AssertionError):audit.inspect(b.getvalue(),'mod.zip',{'scanned_files':0})

    def test_manifest_rejects_invalid_binary(self):
        with self.assertRaises(AssertionError):repack.patch_manifest(struct.pack('<HHI',3,8,9))

if __name__=='__main__':unittest.main()
