#!/usr/bin/env python3
"""Render the real localized editors with an isolated save directory (no ROM)."""
from pathlib import Path
import argparse
import os
import subprocess
import tempfile

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--root', type=Path, default=Path(__file__).resolve().parents[2])
parser.add_argument('--output', type=Path, required=True)
parser.add_argument('--love', required=True)
args = parser.parse_args()
root, out = args.root.resolve(), args.output.resolve()
out.mkdir(parents=True, exist_ok=True)
with tempfile.TemporaryDirectory(prefix='jp-editors-qa-') as temporary:
    stage = Path(temporary)
    app = stage/'app'
    app.mkdir()
    (app/'main.lua').symlink_to(root/'tests/jp_localized_editors_love/main.lua')
    (app/'conf.lua').write_text('function love.conf(t) t.identity="jp-localized-editor-qa";t.window.vsync=0 end\n')
    for name in ['src', 'data', 'assets', 'tools', 'vendor']:
        (app/name).symlink_to(root/name, target_is_directory=True)
    env = dict(os.environ, SDL_VIDEODRIVER='offscreen', LIBGL_ALWAYS_SOFTWARE='1',
               ALSOFT_DRIVERS='null', XDG_DATA_HOME=str(stage/'save'), JP_EDITORS_QA_OUT=str(out))
    result = subprocess.run([args.love, str(app)], env=env, capture_output=True, text=True, timeout=55)
    (out/'console.log').write_text(result.stdout + result.stderr)
    print(result.stdout + result.stderr, end='')
    raise SystemExit(result.returncode)
