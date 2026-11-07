#!/usr/bin/env python3
"""Verify exact jp.34 -> jp.35 managed upgrades."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import zipfile

ROOT = Path(__file__).resolve().parents[2]
BASES = {
    'jp34': ('f81a86629b7cdcc92fa80bca764bb2d23af1faa5e21dec3154780f8378c8ae30', '2.0.14+jp.18'),
}
FILES = (
    'src/mods/JapaneseStarterPack.lua', 'src/mods/JapaneseRendererMigration.lua',
    'src/core/SaveData.lua', 'src/mods/LauncherMods.lua',
    'assets/jp-mods/catalog.json', 'assets/jp-mods/managed-renderers.json',
    'assets/jp-mods/upgrades-jp29.json', 'assets/jp-mods/upgrades-jp34.json',
    'assets/jp-mods/DRAMALESS_SHAPE.zip',
    'tests/jp35_mod_upgrade_love/main.lua', 'tests/jp35_mod_upgrade_love/conf.lua',
    'tests/jp35_mod_upgrade_love/run.py',
)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for name in BASES:
        parser.add_argument('--' + name, type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--love', default=os.getenv('LOVE', 'love'))
    args = parser.parse_args()
    bases = {name: getattr(args, name).resolve() for name in BASES}
    for name, path in bases.items():
        assert hashlib.sha256(path.read_bytes()).hexdigest() == BASES[name][0], name
    out = args.output.resolve()
    out.mkdir(parents=True, exist_ok=True)
    cases = {}
    with tempfile.TemporaryDirectory(prefix='jp35-upgrade-') as tmp:
        temporary = Path(tmp)
        env = os.environ.copy()
        env.update(JP_UPGRADE_ROOT=str(ROOT), XDG_DATA_HOME=str(temporary / 'data'),
                   XDG_CONFIG_HOME=str(temporary / 'config'), SDL_VIDEODRIVER='offscreen',
                   LIBGL_ALWAYS_SOFTWARE='1', ALSOFT_DRIVERS='null')
        for label, path in bases.items():
            game = temporary / (label + '.love')
            with zipfile.ZipFile(path) as archive:
                game.write_bytes(archive.read('assets/game.love'))
            env.update(JP_UPGRADE_BASELINE=str(game), JP_UPGRADE_LABEL=label,
                       JP_UPGRADE_VERSION=BASES[label][1],
                       JP_UPGRADE_FULL='1' if label == 'jp34' else '0')
            stage = temporary / label
            stage.mkdir()
            for name in ('main.lua', 'conf.lua'):
                shutil.copy2(ROOT / 'tests/jp35_mod_upgrade_love' / name, stage / name)
            for name in ('assets', 'src'):
                (stage / name).symlink_to(ROOT / name, target_is_directory=True)
            result = subprocess.run([args.love, str(stage)], env=env,
                                    capture_output=True, text=True)
            (out / (label + '.log')).write_text(result.stdout + result.stderr)
            cases[label] = {'exit_code': result.returncode,
                            'checks': result.stdout.count('PASS ')}
            if result.returncode:
                print('\n'.join((result.stdout + result.stderr).splitlines()[-25:]))
    report = {'exit_code': max(abs(case['exit_code']) for case in cases.values()),
              'checks': sum(case['checks'] for case in cases.values()),
              'cases': cases, 'bases_sha256': {name: value[0] for name, value in BASES.items()},
              'files_sha256': {name: hashlib.sha256((ROOT / name).read_bytes()).hexdigest()
                               for name in FILES}}
    (out / 'real.json').write_text(json.dumps(report, indent=2) + '\n')
    print(json.dumps(report))
    raise SystemExit(report['exit_code'])


if __name__ == '__main__':
    main()
