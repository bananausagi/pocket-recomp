#!/usr/bin/env python3
"""PocketRecomp personal-line build, re-signed with the ORIGINAL
jp-series key (recovered from the Drive signing backup into
../signing-original/).  Identical pipeline to build.py; only the
signing identity differs, so this APK can overwrite a jp.91-preview2
install.  The script asserts the resulting signer certificate equals
the jp-series fingerprint before declaring success.

Reproduces the jp-series build method (HANDOVER section 5.2) on this
machine, folded into a single reproducible script:

  1. Verify the jp.90 baseline APK by SHA-256 (the native shell donor).
  2. Zip game/ into game.love, asserting that no ROM / save / key material
     and no ROM-generated cache trees are inside.  This hygiene check is
     load-bearing -- do not remove it (HANDOVER section 8).
  3. Rebuild the APK from the baseline: every entry byte-identical except
     assets/game.love (new payload) and AndroidManifest.xml
     (versionCode / versionName patched by build_deps.repack_controls).
  4. 16 KB alignment, then sign with the original jp-series key in
     ../signing-original/.
     build-tools 35's `zipalign -P 16` is unavailable on this machine
     (only 34, which lacks -P), so build.py performs the identical
     transformation itself: STORED .so entries are padded (via a local
     extra field) to 16384-byte data offsets, other STORED entries to 4,
     exactly what zipalign -P 16 -f 4 produces.
  5. Verify: apksigner, zipalign -c, aapt2 badging, entry-set and
     byte-identity against the baseline, game.love content assertions.
     Writes build/build-verification.json.

The signing key is the original jp-series key from the Drive backup
(gen1recomp-jp-android-private-signing-backup.zip), so this APK can
overwrite a jp.91-preview2 install; see README.md.

usage: python3 build.py
"""
from pathlib import Path
from zipfile import ZipFile, ZIP_DEFLATED, ZipInfo
import hashlib, json, os, re, struct, subprocess, sys

ROOT = Path(__file__).resolve().parent           # clean/
WORK = ROOT.parent                               # ~/workspace/pocket_recomp
BASE_APK = WORK / 'base' / 'Pocket-Recomp-jp90-20261022.apk'
BASE_SHA256 = '03c2c989d1dd2593faaf883cfbd0433128101ea6ae9464d47f294e857f461a0c'
PREVIEW2_APK = WORK / 'base' / 'Pocket-Recomp-jp91-preview2-20261023.apk'
PACKAGE = 'org.gen1recomp.japanese.preview'
OLD_CODE, NEW_CODE = 93, 95
OLD_VERSION = '0.2.90-jp.90'
NEW_VERSION = '0.2.91-jp.91-personal'
LABEL = 'ポケットリコンプ'
GAME = ROOT / 'game'
BUILD = ROOT / 'build'
OUT_APK = ROOT / 'PocketRecomp-personal.apk'
SIGN_DIR = WORK / 'signing-original'
KEYSTORE = SIGN_DIR / 'debug.keystore'
PASS_FILE = SIGN_DIR / 'keystore.pass'
ALIAS = 'androiddebugkey'
JP_CERT_SHA256 = ('c469ecb3fcd30df41bbd2b9dfea887404a65c71e'
                  '778e200a57c112c51f92f39c')
SDK_BT = Path.home() / 'android-sdk' / 'build-tools' / '34.0.0'
JDK = Path.home() / 'workspace' / 'tools' / 'jdk17'

sys.path.insert(0, str(ROOT / 'build_deps'))
from repack_controls import patch_manifest  # noqa: E402

sha = lambda b: hashlib.sha256(b).hexdigest()  # noqa: E731
FORBIDDEN_SUFFIXES = ('.gb', '.gbc', '.gba', '.sav', '.srm',
                      '.p12', '.keystore', '.jks', '.pk8')
GENERATED_DIRS = {'crystal_jp', 'gold_jp', 'silver_jp'}
SIGNATURE = re.compile(r'META-INF/(?:MANIFEST\.MF|[^/]+\.(?:SF|RSA|DSA|EC))$',
                       re.I)

ENV = dict(os.environ)
ENV['PATH'] = f"{JDK / 'bin'}:{SDK_BT}:{ENV.get('PATH', '')}"
ENV['JAVA_HOME'] = str(JDK)
ENV['PR_SIGN_PASS'] = PASS_FILE.read_text().strip()


def _local_entries(data):
    """Yield (offset, name, method, comp_size, name_len, extra_len,
    data_offset) for each local file header, in file order."""
    pos = 0
    while data[pos:pos + 4] == b'PK\x03\x04':
        (sig, _ver, flags, method, _mt, _md, _crc, comp, _raw,
         nlen, elen) = struct.unpack_from('<IHHHHHIIIHH', data, pos)
        assert not flags & 0x08, 'data descriptor present; unsupported'
        name = data[pos + 30:pos + 30 + nlen].decode('utf-8')
        yield pos, name, method, comp, nlen, elen, pos + 30 + nlen + elen
        pos += 30 + nlen + elen + comp


def align_apk(src: Path, dst: Path):
    """zipalign -P 16 equivalent: pad STORED entries so .so data starts
    on a 16384-byte boundary and other stored data on a 4-byte one, by
    growing the local extra field; central-directory offsets are fixed
    up to match.  Entry bytes themselves are never touched."""
    data = src.read_bytes()
    out = bytearray()
    shifts = {}  # old local-header offset -> new offset
    for pos, name, method, comp, nlen, elen, data_off in _local_entries(data):
        shifts[pos] = len(out)
        header = bytearray(data[pos:pos + 30 + nlen + elen])
        if method == 0:  # STORED
            align = 16384 if name.endswith('.so') else 4
            base = len(out) + 30 + nlen + elen
            need = (align - (base % align)) % align
            if need:
                extra_len = need if need >= 4 else need + align
                pad = struct.pack('<HH', 0xFFFF, extra_len - 4) \
                    + b'\0' * (extra_len - 4)
                header += pad
                struct.pack_into('<H', header, 28, elen + extra_len)
        out += header
        out += data[data_off:data_off + comp]
    # The central directory begins right after the final entry's data;
    # copy it (and the end record) across, remapping each entry's
    # local-header offset by the shift its header accumulated.
    entries = list(_local_entries(data))
    if entries:
        _p, _n, _m, lcomp, _nl, _el, ldoff = entries[-1]
        cd_off = ldoff + lcomp
    else:
        cd_off = 0
    tail = bytearray(data[cd_off:])
    p = 0
    while tail[p:p + 4] == b'PK\x01\x02':
        # central header: fixed 46 bytes; name/extra/comment lens at 28/30/32,
        # local-header offset at 42
        cnlen, celen, cclen = struct.unpack_from('<HHH', tail, p + 28)
        old_off = struct.unpack_from('<I', tail, p + 42)[0]
        struct.pack_into('<I', tail, p + 42, shifts[old_off])
        p += 46 + cnlen + celen + cclen
    cd_new = len(out)
    out += tail
    # the end record still points at the old central-directory offset
    eocd = out.rfind(b'PK\x05\x06')
    assert eocd > 0, 'no end-of-central-directory record'
    struct.pack_into('<I', out, eocd + 16, cd_new)
    dst.write_bytes(bytes(out))


def check_alignment(path: Path):
    """Assert the -P 16 invariants on a finished APK."""
    data = path.read_bytes()
    for _pos, name, method, _comp, _nl, _el, data_off in _local_entries(data):
        if method == 0:
            want = 16384 if name.endswith('.so') else 4
            assert data_off % want == 0, f'{name}: data offset {data_off} % {want}'


def run(args, log_name):
    r = subprocess.run([str(a) for a in args], capture_output=True,
                       text=True, env=ENV)
    (BUILD / log_name).write_text(r.stdout + r.stderr)
    assert r.returncode == 0, f"{args[0]} failed: {(r.stdout + r.stderr)[-800:]}"
    return r.stdout + r.stderr


def main():
    BUILD.mkdir(exist_ok=True)

    # --- 0. constants stay in sync with the in-game update notifier ------
    pu = (GAME / 'src/jp/PersonalUpdate.lua').read_text()
    assert re.search(rf'CURRENT_CODE = {NEW_CODE}\b', pu), \
        'PersonalUpdate.CURRENT_CODE out of sync with build.py'
    assert f'CURRENT_NAME = "{NEW_VERSION}"' in pu, \
        'PersonalUpdate.CURRENT_NAME out of sync with build.py'

    # --- 1. baseline ------------------------------------------------------
    assert BASE_APK.exists(), f'baseline APK missing: {BASE_APK}'
    assert sha(BASE_APK.read_bytes()) == BASE_SHA256, 'baseline sha256 mismatch'
    assert KEYSTORE.exists() and PASS_FILE.exists(), 'original key missing'

    # --- 2. game.love from the tree, with the hygiene assertions ---------
    files = sorted(p for p in GAME.rglob('*') if p.is_file())
    names = []
    for p in files:
        rel = p.relative_to(GAME).as_posix()
        assert not rel.endswith(('.orig', '.bak')), rel
        assert not rel.lower().endswith(FORBIDDEN_SUFFIXES), rel
        assert not (set(Path(rel).parts) & GENERATED_DIRS), rel
        assert not re.match(r'(?:data|assets)/generated/', rel), rel
        names.append(rel)
    love_path = BUILD / 'game.love'
    with ZipFile(love_path, 'w', ZIP_DEFLATED) as z:
        for p, rel in zip(files, names):
            info = ZipInfo(rel, date_time=(1980, 1, 1, 0, 0, 0))
            info.compress_type = ZIP_DEFLATED
            info.external_attr = 0o644 << 16
            z.writestr(info, p.read_bytes())
    with ZipFile(love_path) as z:
        assert z.testzip() is None
        inside = z.namelist()
        assert set(inside) == set(names) and len(inside) == len(names)
        assert not any(n.lower().endswith(FORBIDDEN_SUFFIXES) for n in inside)
        assert not any(set(Path(n).parts) & GENERATED_DIRS for n in inside)
    love_sha = sha(love_path.read_bytes())
    print(f'game.love: {len(names)} files, sha256 {love_sha}')

    # --- 3. unsigned APK: baseline shell + new love + patched manifest ---
    unsigned = BUILD / 'unsigned.apk'
    with ZipFile(BASE_APK) as apk, ZipFile(unsigned, 'w') as new:
        for item in apk.infolist():
            if SIGNATURE.fullmatch(item.filename):
                continue
            b = apk.read(item.filename)
            if item.filename == 'assets/game.love':
                b = love_path.read_bytes()
            elif item.filename == 'AndroidManifest.xml':
                b = patch_manifest(
                    b, source_code=OLD_CODE, target_code=NEW_CODE,
                    source_version=OLD_VERSION, target_version=NEW_VERSION,
                    source_label=LABEL, source_package=PACKAGE)
            new.writestr(item, b)

    # --- 4. align + sign ---------------------------------------------------
    aligned = BUILD / 'aligned.apk'
    align_apk(unsigned, aligned)
    check_alignment(aligned)
    if OUT_APK.exists():
        OUT_APK.unlink()
    run([SDK_BT / 'apksigner', 'sign',
         '--ks', KEYSTORE, '--ks-key-alias', ALIAS,
         '--ks-pass', 'env:PR_SIGN_PASS', '--key-pass', 'env:PR_SIGN_PASS',
         '--v4-signing-enabled', 'false',
         '--out', OUT_APK, aligned], 'sign.log')

    # --- 5. verification ---------------------------------------------------
    sig_out = run([SDK_BT / 'apksigner', 'verify', '--verbose',
                   '--print-certs', OUT_APK], 'signature.log')
    m = re.search(r'Signer #1 certificate SHA-256 digest: (\w+)', sig_out)
    assert m, 'no signer cert in apksigner output'
    cert_sha = m.group(1)
    assert cert_sha == JP_CERT_SHA256, \
        f'signer is not the jp-series key: {cert_sha}'
    check_alignment(OUT_APK)
    # sanity: the stock tool's plain 4-byte check must pass too
    run([SDK_BT / 'zipalign', '-c', '-v', '4', OUT_APK], 'alignment.log')
    badging = run([SDK_BT / 'aapt2', 'dump', 'badging', OUT_APK],
                  'badging.log')
    assert f"name='{PACKAGE}'" in badging
    assert f"versionCode='{NEW_CODE}'" in badging
    assert f"versionName='{NEW_VERSION}'" in badging
    assert LABEL in badging, 'UTF-8 label lost'

    with ZipFile(BASE_APK) as old, ZipFile(OUT_APK) as new:
        old_names = {n for n in old.namelist() if not SIGNATURE.fullmatch(n)}
        new_names = {n for n in new.namelist() if not SIGNATURE.fullmatch(n)}
        assert old_names == new_names, (old_names ^ new_names)
        for n in old_names:
            if n in ('AndroidManifest.xml', 'assets/game.love'):
                continue
            assert old.read(n) == new.read(n), f'entry changed: {n}'
        final_love = new.read('assets/game.love')
        assert sha(final_love) == love_sha
        with ZipFile(__import__('io').BytesIO(final_love)) as z:
            assert z.testzip() is None
            assert not any(
                x.lower().endswith(FORBIDDEN_SUFFIXES) for x in z.namelist())

    report = {
        'line': 'personal (game91 = jp.91-preview2 + WIP overlay + PersonalUpdate)',
        'file': OUT_APK.name,
        'package': PACKAGE,
        'version': NEW_VERSION,
        'versionCode': NEW_CODE,
        'bytes': OUT_APK.stat().st_size,
        'sha256': sha(OUT_APK.read_bytes()),
        'md5': hashlib.md5(OUT_APK.read_bytes()).hexdigest(),
        'baselineApk': BASE_APK.name,
        'baselineSha256': BASE_SHA256,
        'gameLoveSha256': love_sha,
        'gameFiles': len(names),
        'signerCertSha256': cert_sha,
        'sameSigningCertificateAsJpSeries': cert_sha == JP_CERT_SHA256,
        'signingKey': 'original jp-series key (Drive backup)',
        'alignment16KB': True,
        'deviceTested': False,
    }
    (BUILD / 'build-verification.json').write_text(
        json.dumps(report, ensure_ascii=False, indent=2))
    print('VERIFIED', OUT_APK.name, report['sha256'], report['bytes'])


if __name__ == '__main__':
    main()
