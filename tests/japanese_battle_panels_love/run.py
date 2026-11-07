#!/usr/bin/env python3
"""Stage ROM-free battle panels and run the actual native font renderer."""
import argparse, os, pathlib, shutil, subprocess, tempfile
parser=argparse.ArgumentParser(description=__doc__)
parser.add_argument('--love',default='love')
parser.add_argument('--output',type=pathlib.Path,required=True)
a=parser.parse_args();root=pathlib.Path(__file__).resolve().parents[2]
out=a.output.resolve();out.mkdir(parents=True,exist_ok=True)
with tempfile.TemporaryDirectory(prefix='jp-panels-qa-') as temporary:
    app=pathlib.Path(temporary)/'app';app.mkdir()
    for name in ['main.lua','conf.lua']:
        shutil.copy2(root/'tests/japanese_battle_panels_love'/name,app/name)
    for name in ['src','assets','data','tools','tests']:
        (app/name).symlink_to(root/name,target_is_directory=True)
    env=dict(os.environ,JP_PANELS_ROOT=str(root),JP_PANELS_OUT=str(out),
             SDL_VIDEODRIVER='offscreen',LIBGL_ALWAYS_SOFTWARE='1',
             XDG_DATA_HOME=str(pathlib.Path(temporary)/'save'))
    result=subprocess.run([a.love,str(app)],env=env,text=True,
                          stdout=subprocess.PIPE,stderr=subprocess.STDOUT)
    (out/'run.log').write_text(result.stdout)
    print(result.stdout,end='')
    raise SystemExit(result.returncode)
