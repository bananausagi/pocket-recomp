"""Regression cases for the localization audit's scope and Lua parsing."""
import contextlib
import io
import json
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0,str(Path(__file__).resolve().parents[1]/"tools"))
import audit_japanese_text as audit


class AuditTests(unittest.TestCase):
    def test_lua_strings_and_comments(self):
        source='''-- Strings("comment")
--[=[ Strings("long comment") ]=]
Strings("line\\nnext\\xc3\\xa9")
Strings([=[long
line]=])
'''
        strings=[t for t in audit.lex(source) if t.kind=="string"]
        self.assertEqual([t.value for t in strings],["line\nnexté","long\nline"])
        self.assertEqual([t.line for t in strings],[3,4])

    def test_nested_arguments_and_escaped_quote(self):
        tokens=audit.lex('self:romText("key", flag and "It\\\"s %s" or "Other %s", f({a=1,b=2}))')
        name,at=audit.call_name(tokens,0)
        args,_=audit.arguments(tokens,at)
        self.assertEqual(name,"self:romText")
        self.assertEqual(len(args),3)
        self.assertEqual(audit.literal(args[0]),"key")
        self.assertIsNone(audit.literal(args[1]))

    def test_format_signature_order_not_only_count(self):
        self.assertEqual(audit.signature("%s %+03d %.1f %% %q"),["s","d","f","q"])
        self.assertNotEqual(audit.signature("%s %d"),audit.signature("%d %s"))
        self.assertEqual(audit.signature("100%% full %%s"),[])

    def test_bounded_generated_catalog_no_eval(self):
        source='for n=1,3 do text["ROUTE "..n]=n.."ばん" end'
        self.assertEqual(list(audit.generated_catalog_entries(source)),
                         [("ROUTE 1","1ばん",1),("ROUTE 2","2ばん",1),("ROUTE 3","3ばん",1)])
        self.assertEqual(list(audit.generated_catalog_entries('for n=1,3 do text["X"..n]=os.execute("bad") end')),[])

    def test_technical_labels_are_not_identifiers_or_english(self):
        self.assertEqual(audit.english_kind("PP %2d/%2d"),"technical_label")
        self.assertEqual(audit.english_kind("%s (%s)"),"format_or_symbols")
        self.assertEqual(audit.english_kind("OPP_SCIENTIST"),"identifier")
        self.assertEqual(audit.english_kind("Transfer this save"),"english")

    def test_end_to_end_review_categories_and_font_validation(self):
        with tempfile.TemporaryDirectory() as temp:
            root=Path(temp)
            def put(name,text):
                p=root/name;p.parent.mkdir(parents=True,exist_ok=True);p.write_text(text)
            put("tools/modkit.py","def harvest_engine_strings(repo): return []\n")
            put("tools/rom_manifest_red_jp.json",json.dumps({"fontCharmap":[{"seq":"あ"}]}))
            put("assets/jp-mods/catalog.json","[]")
            put("src/core/JapaneseStrings.lua",'return {["Ready"]="あ", ["%s %d"]="%d %s", ["Font"]="漢", ["Empty"]="", ["SkinStudio: Pick"]="あ"}')
            put("src/battle/Test.lua",'''-- Strings("Never harvested")
Strings("Ready")
Strings("Missing")
Strings("Empty")
Strings.source("Deferred")
self:romText("KEY", flag and "Choice one" or "Choice two", name)
romText(data,"KEY","Fallback")
Font.draw("Raw text",0,0)
Font.draw(Strings("Ready"),0,0)
Font.draw("HP",0,0)
Font.draw("OPP_SCIENTIST",0,0)
Font.draw(Strings("Left")..Strings("Right"),0,0)
''')
            put("src/ui/SkinStudio.lua",'local function tr(source) return source end; Font.draw(tr("Pick"),0,0); tr(flag and "Pick" or "Pick")')
            put("src/battle/gen2/Test.lua",'Strings("Gen2 excluded")')
            with contextlib.redirect_stdout(io.StringIO()):
                report=audit.run(root,root/"result")
            sources={r["source"] for r in report["missing_calls"]}
            self.assertEqual(sources,{"Missing","Deferred","Choice one","Choice two","Fallback","Left","Right"})
            self.assertEqual([r["source"] for r in report["raw_review_candidates"]],["Raw text"])
            self.assertEqual(len(report["format_signature_errors"]),1)
            self.assertEqual(report["native_font_issues"][0]["unsupported"],["漢"])
            self.assertEqual(report["exclusions"]["unsupported_generation"],1)


if __name__=="__main__": unittest.main()
