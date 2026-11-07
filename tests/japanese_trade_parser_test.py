"""ROM-free regression for the JP inline trade-table format."""
import json
from pathlib import Path
import sys
import tempfile
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "tools"))
from extract.field import parse_trades


class JapaneseTrades(unittest.TestCase):
    def parse(self, text):
        with tempfile.TemporaryDirectory() as root:
            path = Path(root) / "data/events/trades.asm"
            path.parent.mkdir(parents=True)
            path.write_text(text)
            return parse_trades(root)

    def test_inline_records_keep_japanese_rules_and_strip_padding(self):
        rows = self.parse('TradeMons:\n'
            '\tdb RAICHU, ELECTRODE, TRADE_DIALOGSET_EVOLUTION, "おマル@@"\n'
            '\tdb NIDORAN_F, NIDORAN_M, TRADE_DIALOGSET_HAPPY, "チャッピー"\n')
        self.assertEqual(rows, [
            dict(give="RAICHU", get="ELECTRODE", dialogset=2, nickname="おマル"),
            dict(give="NIDORAN_F", get="NIDORAN_M", dialogset=3, nickname="チャッピー")])

    def test_modern_macro_records_are_unchanged(self):
        rows = self.parse('npctrade ABRA, MR_MIME, TRADE_DIALOGSET_CASUAL, "MARCEL"\n')
        self.assertEqual(rows, [dict(give="ABRA", get="MR_MIME", dialogset=1, nickname="MARCEL")])

    def test_shipped_manifest_has_all_primary_rows(self):
        path = Path(__file__).resolve().parents[1] / "tools/rom_manifest_red_jp.json"
        data = json.loads(path.read_text())
        rows = data["field"]["trades"]
        self.assertEqual(len(rows), 10)
        self.assertEqual(rows[7], dict(give="RAICHU", get="ELECTRODE", dialogset=2, nickname="おマル"))
        self.assertEqual((rows[4]["dialogset"], rows[5]["dialogset"]), (2, 2))
        self.assertEqual((rows[9]["give"], rows[9]["get"]), ("NIDORAN_F", "NIDORAN_M"))
        for row in rows:
            self.assertNotIn("@", row["nickname"])
            for prefix in ("_WannaTrade", "_NoTrade", "_WrongMon", "_Thanks", "_AfterTrade"):
                label = prefix + str(row["dialogset"]) + "Text"
                self.assertIn(label, data["text"]["labels"])
                self.assertIn(label, data["jpTextSymbols"])


if __name__ == "__main__":
    unittest.main()
