#!/usr/bin/env python3
"""Assemble a test tree for the personal line (adapted from setup_tb91.py).

Copies game/ + tests/ into the target dir and expands the bundled
DRAMALESS_SHAPE mod into vendor/jp-mods/, which several tests load.
The target dir is deleted and recreated on every run.

usage: python3 tools/setup_tb.py [tb_dir]   (default: build/tb_new)
"""
from pathlib import Path
import shutil, sys
from zipfile import ZipFile

ROOT = Path(__file__).resolve().parent.parent  # clean/
app = Path(sys.argv[1]) if len(sys.argv) > 1 else ROOT / 'build' / 'tb_new'
if not app.is_absolute():
    app = ROOT / app
if app.exists():
    shutil.rmtree(app)
shutil.copytree(ROOT / 'game', app,
                ignore=shutil.ignore_patterns('*.orig', '*.bak'))
shutil.copytree(ROOT / 'tests', app / 'tests', dirs_exist_ok=True)
with ZipFile(app / 'assets/jp-mods/DRAMALESS_SHAPE.zip') as z:
    for n in z.namelist():
        assert '..' not in Path(n).parts
        if n.endswith('/'):
            continue
        p = app / 'vendor/jp-mods/DRAMALESS_SHAPE' / n
        p.parent.mkdir(parents=True, exist_ok=True)
        p.write_bytes(z.read(n))
print(app, 'ready')
