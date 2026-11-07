"""Synthetic symbol metadata: no ROM files are consumed or produced."""
import copy
from pathlib import Path
import sys
import tempfile
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "tools"))
from make_japanese_revision import BASE_SHA1, build


class RevisionMetadata(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.old = Path(self.temp.name) / "old.sym"
        self.new = Path(self.temp.name) / "new.sym"
        self.old.write_text("09:7fc0 TextOriginal\n09:7fc0 StableAlias\n02:4100 Audio\n")
        self.new.write_text("09:7f9a StableAlias\n02:4100 Audio\n")
        self.manifest = {"romSha1": BASE_SHA1,
            "symbols": {"EngineAlias": [9, 0x7fc0]},
            "text": {"lengths": {"EngineAlias": 64}},
            "audio": {"entry": {"bank": 2, "address": 0x4100}}}

    def run_build(self):
        return build(self.manifest, self.old, self.new)

    def test_preserves_engine_alias_after_public_label_rename(self):
        original = copy.deepcopy(self.manifest)
        result = self.run_build()
        self.assertEqual(result["symbolChanges"], {"EngineAlias": {"from": [9, 0x7fc0], "to": [9, 0x7f9a]}})
        self.assertEqual(self.manifest, original)
        self.assertEqual(result["textLengthChanges"], {"EngineAlias": {"from": 64, "to": 102}})
        self.assertEqual(result["provenance"]["inlineAddressesChecked"], 1)
        self.assertEqual(result, self.run_build())

    def test_ambiguous_alias_is_not_guessed(self):
        self.new.write_text(self.new.read_text()+"09:7f80 TextOriginal\n")
        with self.assertRaisesRegex(ValueError, "ambiguous"):
            self.run_build()

    def test_missing_address_is_not_guessed(self):
        self.manifest["symbols"]["Missing"] = [9, 0x4100]
        with self.assertRaisesRegex(ValueError, "unresolved"):
            self.run_build()

    def test_moved_inline_data_requires_explicit_implementation(self):
        self.new.write_text(self.new.read_text().replace("02:4100", "02:4120"))
        with self.assertRaisesRegex(ValueError, "inline ROM metadata"):
            self.run_build()

    def test_invalid_relocated_text_is_rejected(self):
        self.old.write_text(self.old.read_text()+"09:7fe0 TextEnd\n")
        self.new.write_text(self.new.read_text()+"08:7fe0 TextEnd\n")
        self.manifest["text"]["lengths"]["EngineAlias"] = 32
        with self.assertRaisesRegex(ValueError, "invalid relocated text span"):
            self.run_build()


if __name__ == "__main__":
    unittest.main()
