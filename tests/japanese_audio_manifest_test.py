"""No ROM/disassembly checkout required: regress SFX table relocation."""
import json
import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools"))
from make_rom_manifest import sfx_keys
from rom_data import SymbolTable


class SoundIds(unittest.TestCase):
    def generate(self, base):
        # Constants are references, not audio programs. The unrelated bank
        # intentionally reuses an ID to catch cross-bank collisions.
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / "constants").mkdir()
            (root / "constants/music_constants.asm").write_text(
                "music_const SFX_POUND, SFX_Pound\n"
                "music_const SFX_DAMAGE, SFX_Damage\n"
                "music_const SFX_SUPER_EFFECTIVE, SFX_Super_Effective\n"
                "music_const SFX_PRESS_AB, SFX_Press_AB_1\n")
            symbols = SymbolTable({
                "SFX_Headers_2": [8, base],
                "SFX_Pound": [8, base + 160 * 3],
                "SFX_Damage": [8, base + 166 * 3],
                "SFX_Super_Effective": [8, base + 176 * 3],
                "SFX_Press_AB_1": [2, base + 160 * 3],
            })
            return sfx_keys(str(root), symbols)

    def test_japanese_relocated_headers(self):
        self.assertEqual(self.generate(0x6C92), {
            "160": "Pound", "166": "Damage", "176": "Super_Effective"})

    def test_overseas_fixed_headers_unchanged(self):
        self.assertEqual(self.generate(0x4000), self.generate(0x6C92))

    def test_committed_manifest_covers_all_battle_headers(self):
        manifest = json.loads((ROOT / "tools/rom_manifest_red_jp.json").read_text())
        keys = manifest["sfxKeys"]
        self.assertEqual(len(keys), 56)
        self.assertEqual(manifest["audio"]["sfxHeaderBases"]["2"],
                         {"bank": 8, "address": 0x6C92})
        for sound_id, name in keys.items():
            header = manifest["audio"]["sfxHeaders"][name]
            self.assertEqual(header["bank"], 8)
            self.assertEqual(header["address"] - 0x6C92, int(sound_id) * 3)
        self.assertEqual(keys, json.loads((ROOT / "tools/rom_manifest.json").read_text())["sfxKeys"])


if __name__ == "__main__":
    unittest.main()
