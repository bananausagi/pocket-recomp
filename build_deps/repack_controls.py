#!/usr/bin/env python3
"""Update jp.18 Lua/assets only; retain all DEX, native code and compiled resources.

Output is unsigned: zipalign -P 16, then apksigner with the previous key.
The binary XML string pool is rebuilt for a changed-length versionName.
"""
import argparse
import hashlib
import json
import re
import struct
from pathlib import Path
from zipfile import ZipFile, ZipInfo

BASE_SHA256 = "11154908284f4cc15ca6a1b1a53b189e607dd440f2bb832ebb31527ef493f042"
VERSION = "0.2.66-jp.31"
APP_NAME = "Kanto Player JP"
ROOT = Path(__file__).resolve().parents[1]


def patch_manifest(raw, *, source_code=18, target_code=31,
                   source_version="0.2.66-jp.18", target_version=VERSION,
                   source_label=APP_NAME, target_label=None, source_package="org.gen1recomp.japanese.preview"):
    """Keep every original XML node; update version and verify the existing Back opt-in."""
    u16 = lambda data, p: struct.unpack_from("<H", data, p)[0]
    u32 = lambda data, p: struct.unpack_from("<I", data, p)[0]
    assert u16(raw, 0) == 3 and u32(raw, 4) == len(raw), "invalid binary XML"
    nodes, strings, utf8, pool_flags = [], [], False, 0
    pos = u16(raw, 2)
    while pos < len(raw):
        kind, header, size = struct.unpack_from("<HHI", raw, pos)
        assert size >= header >= 8 and pos + size <= len(raw)
        node = bytearray(raw[pos:pos+size])
        nodes.append((kind, header, node))
        if kind == 1:
            assert not strings, "multiple string pools"
            count, styles, pool_flags, start, style_start = struct.unpack_from("<IIIII", node, 8)
            assert header == 28 and styles == 0 and style_start == 0, "unexpected styled manifest strings"
            utf8 = bool(pool_flags & 0x100)
            def length(p):
                if utf8:
                    n = node[p]
                    return (((n & 0x7f) << 8) | node[p+1], p+2) if n & 0x80 else (n,p+1)
                n = u16(node,p)
                return (((n & 0x7fff) << 16) | u16(node,p+2),p+4) if n & 0x8000 else (n,p+2)
            for i in range(count):
                p = start + u32(node,header+i*4)
                n,p = length(p)
                if utf8: n,p = length(p)
                else: n *= 2
                strings.append(bytes(node[p:p+n]).decode("utf-8" if utf8 else "utf-16-le"))
        pos += size
    assert source_label in strings, "unexpected app label"
    updated, back = set(), False
    back_name = "enableOnBackInvokedCallback"
    assert back_name in strings, "base is missing the jp.9 Back opt-in"
    back_index = strings.index(back_name)
    for kind, header, node in nodes:
        if kind != 0x102: continue
        ext = header
        tag = strings[u32(node,ext+4)]
        attr_start, attr_size, count = u16(node,ext+8),u16(node,ext+10),u16(node,ext+12)
        assert attr_size == 20
        attrs = {strings[u32(node,ext+attr_start+i*attr_size+4)]:ext+attr_start+i*attr_size for i in range(count)}
        if tag == "manifest":
            for name,a in attrs.items():
                if name == "versionCode":
                    assert node[a+15] in (0x10,0x11) and u32(node,a+16) == source_code
                    struct.pack_into("<I",node,a+16,target_code);updated.add(name)
                elif name == "versionName":
                    assert node[a+15] == 3
                    index=u32(node,a+16);assert strings[index]==source_version
                    strings[index]=target_version;updated.add(name)
                elif name == "package":
                    assert strings[u32(node,a+16)]==source_package
                    updated.add(name)
        if tag == "activity" and "name" in attrs:
            a=attrs["name"]
            if node[a+15]==3 and strings[u32(node,a+16)]=="org.love2d.android.GameActivity":
                assert not back, "duplicate main Activity"
                assert back_name in attrs, "main Activity Back opt-in is missing"
                a=attrs[back_name]
                assert node[a+15]==0x12 and u32(node,a+16)==0xffffffff, "main Activity Back opt-in is disabled"
                back=True
    assert updated=={"versionCode","versionName","package"} and back,(updated,back)
    if target_label is not None:
        strings[strings.index(source_label)]=target_label
    def encoded_length(n):
        if utf8:
            assert n<0x8000
            return bytes([n]) if n<0x80 else bytes([0x80 | (n>>8),n & 0xff])
        return struct.pack("<H",n) if n<0x8000 else struct.pack("<HH",0x8000 | (n>>16),n & 0xffff)
    body, offsets=bytearray(),[]
    for text in strings:
        offsets.append(len(body));units=len(text.encode("utf-16-le"))//2
        if utf8:
            encoded=text.encode("utf-8");body+=encoded_length(units)+encoded_length(len(encoded))+encoded+b"\0"
        else: body+=encoded_length(units)+text.encode("utf-16-le")+b"\0\0"
    body+=bytes((-len(body))%4)
    pool=struct.pack("<HHIIIIII",1,28,28+4*len(strings)+len(body),len(strings),0,pool_flags & ~1,28+4*len(strings),0)
    pool+=b"".join(struct.pack("<I",offset) for offset in offsets)+body
    rebuilt=[];resource_map=False
    for kind,header,node in nodes:
        if kind==1: rebuilt.append(pool)
        elif kind==0x180:
            assert header+4*back_index+4 <= len(node), "missing Back resource ID"
            assert u32(node,header+4*back_index)==16844396, "unexpected Back resource ID"
            rebuilt.append(node)
            resource_map=True
        else: rebuilt.append(node)
    assert resource_map,"missing XML resource map"
    result=bytearray(raw[:u16(raw,2)])+b"".join(rebuilt)
    struct.pack_into("<I",result,4,len(result))
    return bytes(result)


def verify_native_sources():
    """A Lua-only release cannot silently ship modified Java source either."""
    baseline=json.loads((ROOT/"tools/jp19_native_baseline.json").read_text())
    assert baseline["mode"]=="lua-only" and baseline["base_sha256"]==BASE_SHA256
    actual={p.relative_to(ROOT).as_posix():hashlib.sha256(p.read_bytes()).hexdigest()
            for p in (ROOT/"mobile/android").rglob("*")
            if p.is_file() and p.suffix in {".java",".kt"}}
    assert actual==baseline["java_source_sha256"], "native Java sources changed in Lua-only release"
    mods={p.relative_to(ROOT).as_posix():hashlib.sha256(p.read_bytes()).hexdigest()
          for p in (ROOT/"vendor/jp-mods").rglob("*") if p.is_file()
          and p.relative_to(ROOT/"vendor/jp-mods").parts[0] not in {"DRAMALESS_SHAPE", "VOXEL_ASCENDANT"}}
    prior_mods = baseline["mod_source_sha256"]
    allowed = {"vendor/jp-mods/running_shoes/"+n for n in ("JP-ADAPTATION.md", "main.lua", "manifest.json", "tests/running_shoes_test.lua")}
    assert set(baseline["allowed_mod_source_changes"]) == allowed
    assert set(mods) == set(prior_mods), "unrelated MOD source file set changed in jp.31 release"
    assert all(mods[n] == prior_mods[n] for n in mods if n not in allowed), "unrelated MOD source changed in jp.31 release"
    return actual


def main():
    p=argparse.ArgumentParser(description=__doc__)
    for arg in ("base","game","notices","output"):
        p.add_argument("--"+arg,type=Path,required=True)
    p.add_argument("--mode", choices=("lua-only",), default="lua-only",
                   help="jp.31 preserves all compiled native and Java payloads")
    args=p.parse_args()
    verify_native_sources()

    assert hashlib.sha256(args.base.read_bytes()).hexdigest()==BASE_SHA256,"unexpected base APK"
    assert args.output.resolve() not in {args.base.resolve(),args.game.resolve()}
    with ZipFile(args.game) as game:
        version=game.read("src/core/Version.lua").decode()
        assert 'engine = "0.2.66"' in version and f'distribution = "{VERSION}"' in version
        assert 'licenses/UPSTREAM-MIT-bdfac727.txt' in game.namelist()
        assert not any(re.match(r"(?:data|assets)/generated/[^/]+",n) for n in game.namelist())
    with ZipFile(args.base) as old, ZipFile(args.output,"w") as new:
        for item in old.infolist():
            name=item.filename
            if re.match(r"META-INF/(?:MANIFEST\.MF|[^/]+\.(?:SF|RSA|DSA|EC))$",name,re.I): continue
            if name == "assets/game.love": content=args.game.read_bytes()
            elif name == "assets/THIRD_PARTY_NOTICES.txt": content=args.notices.read_bytes()
            elif name == "AndroidManifest.xml": content=patch_manifest(old.read(name))
            elif re.fullmatch(r"res/drawable-(?:m|h|xh|xxh|xxxh)dpi-v4/(?:love|ic_launcher_foreground|ic_shortcut_(?:red|blue|yellow|gold|silver))\.png",name):
                resource = name.removeprefix("res/").replace("-v4/", "/")
                content=old.read(name)
                assert content.startswith(b"\x89PNG\r\n\x1a\n"), "invalid icon"
                assert content==(ROOT/"mobile/android/app/src/main/res"/resource).read_bytes(), "icon changed from jp.18"
            else: content=old.read(name)
            info=ZipInfo(name,item.date_time)
            info.compress_type=item.compress_type
            info.external_attr=item.external_attr
            new.writestr(info,content)
    print(f"Unsigned {VERSION} APK: {args.output}")


if __name__ == "__main__": main()
