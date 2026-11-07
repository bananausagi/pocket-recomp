#!/usr/bin/env python3
"""Run a source tree's actual main.lua with isolated storage and scripted UI input."""
import argparse
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile

p = argparse.ArgumentParser(description=__doc__)
p.add_argument('--root', type=Path, required=True)
p.add_argument('--output', type=Path, required=True)
p.add_argument('--scenario', type=Path, required=True)
p.add_argument('--love', type=Path, required=True)
p.add_argument('--width', type=int, required=True)
p.add_argument('--height', type=int, required=True)
args = p.parse_args()
root, out = args.root.resolve(), args.output.resolve()
out.mkdir(parents=True, exist_ok=True)
config = json.loads(args.scenario.read_text())
config.update(width=args.width, height=args.height)
(out/'config.json').write_text(json.dumps(config,ensure_ascii=False,indent=2)+'\n')
with tempfile.TemporaryDirectory(prefix='jp-main-launcher-qa-') as temporary:
    stage = Path(temporary)
    app = stage/'app'; app.mkdir()
    shutil.copyfile(Path(__file__).with_name('main.lua'),app/'main.lua')
    (app/'conf.lua').write_text('''local root=assert(os.getenv("JP_MAIN_QA_ROOT"))
assert(loadfile(root.."/conf.lua"))()
local old=love.conf
function love.conf(t)
  old(t)
  t.window.width=tonumber(os.getenv("JP_MAIN_QA_WIDTH"))
  t.window.height=tonumber(os.getenv("JP_MAIN_QA_HEIGHT"))
  t.window.minwidth=160;t.window.minheight=144;t.window.vsync=0
end
''')
    for path in root.iterdir():
        if path.name in ('main.lua','conf.lua','portable.txt') or path.name.startswith('.'):
            continue
        if path.name in ('assets','data'):
            target=app/path.name;target.mkdir()
            for child in path.iterdir():
                if child.name != 'generated':
                    (target/child.name).symlink_to(child, target_is_directory=child.is_dir())
        else:
            (app/path.name).symlink_to(path,target_is_directory=path.is_dir())
    env={k:v for k,v in os.environ.items() if not k.startswith('POKEPORT_')}
    env.update(SDL_VIDEODRIVER='offscreen',LIBGL_ALWAYS_SOFTWARE='1',ALSOFT_DRIVERS='null',
               JP_MAIN_QA_ROOT=str(root),JP_MAIN_QA_OUTPUT=str(out),
               JP_MAIN_QA_CONFIG=str(out/'config.json'),JP_MAIN_QA_WIDTH=str(args.width),
               JP_MAIN_QA_HEIGHT=str(args.height),XDG_DATA_HOME=str(stage/'isolated-save'))
    result=subprocess.run([str(args.love),str(app),'--launcher'],env=env,stdout=subprocess.PIPE,
                          stderr=subprocess.STDOUT,text=True,timeout=55)
    (out/'console.log').write_text(result.stdout)
    print(result.stdout,end='')
    # Save only the report of generated filenames, never transient settings or mods.
    files=[str(v.relative_to(stage/'isolated-save')) for v in (stage/'isolated-save').rglob('*') if v.is_file()]
    (out/'isolated-files.json').write_text(json.dumps(files,ensure_ascii=False,indent=2)+'\n')
    raise SystemExit(result.returncode)
