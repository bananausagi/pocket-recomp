#!/usr/bin/env python3
"""Exercise jp.20 restoration using the exact delivered jp.18 and jp.19 APKs."""
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
    'jp18': '11154908284f4cc15ca6a1b1a53b189e607dd440f2bb832ebb31527ef493f042',
    'jp19': '6d79e86fb6801e6478436495cd0dd508e8d70600359a2895875fd74d76c9de8d',
}
FILES = (
    'src/mods/JapaneseStarterPack.lua', 'src/mods/JapaneseRendererMigration.lua',
    'assets/jp-mods/catalog.json', 'assets/jp-mods/managed-renderers.json',
    'assets/jp-mods/upgrades-jp19.json', 'assets/jp-mods/DRAMALESS_SHAPE.zip',
    'tests/jp20_mod_upgrade_love/main.lua',
)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--jp18', type=Path, required=True)
    parser.add_argument('--jp19', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--love', default=os.getenv('LOVE', 'love'))
    args = parser.parse_args()
    bases = {name: getattr(args, name).resolve() for name in BASES}
    for name, path in bases.items():
        assert hashlib.sha256(path.read_bytes()).hexdigest() == BASES[name], name
    out = args.output.resolve()
    out.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix='jp20-upgrade-') as tmp:
        temporary = Path(tmp)
        stage = temporary / 'fixture'
        stage.mkdir()
        for name in ('main.lua', 'conf.lua'):
            shutil.copy2(ROOT / 'tests/jp20_mod_upgrade_love' / name, stage / name)
        for name in ('assets', 'src'):
            (stage / name).symlink_to(ROOT / name, target_is_directory=True)
        env = os.environ.copy()
        env.update(JP_UPGRADE_ROOT=str(ROOT), XDG_DATA_HOME=str(temporary / 'data'),
                   XDG_CONFIG_HOME=str(temporary / 'config'), SDL_VIDEODRIVER='offscreen',
                   LIBGL_ALWAYS_SOFTWARE='1', ALSOFT_DRIVERS='null')
        for label, path in bases.items():
            game = temporary / (label + '.love')
            with zipfile.ZipFile(path) as archive:
                game.write_bytes(archive.read('assets/game.love'))
            env['JP_UPGRADE_' + label.upper()] = str(game)
        result = subprocess.run([args.love, str(stage)], env=env, capture_output=True, text=True)
        (out / 'real.log').write_text(result.stdout + result.stderr)
        report = {'exit_code': result.returncode, 'checks': result.stdout.count('PASS '),
                  'bases_sha256': BASES,
                  'files_sha256': {name: hashlib.sha256((ROOT / name).read_bytes()).hexdigest()
                                   for name in FILES}}
        (out / 'real.json').write_text(json.dumps(report, indent=2) + '\n')
        print(json.dumps(report))
        if result.returncode:
            print('\n'.join((result.stdout + result.stderr).splitlines()[-25:]))
        raise SystemExit(result.returncode)


if __name__ == '__main__':
    main()
