#!/usr/bin/env python3
"""Render jp29's overbroad cut and jp30's shallow camera clearance on real GL."""
import argparse, os, pathlib, shutil, subprocess, tempfile
p=argparse.ArgumentParser(description=__doc__)
p.add_argument('--love',default='love');p.add_argument('--output',type=pathlib.Path,required=True)
p.add_argument('--before',type=pathlib.Path,required=True)
a=p.parse_args();root=pathlib.Path(__file__).resolve().parents[2];out=a.output.resolve();out.mkdir(parents=True,exist_ok=True)
with tempfile.TemporaryDirectory(prefix='jp30-clearance-') as tmp:
    app=pathlib.Path(tmp)/'app';app.mkdir()
    for name in ('main.lua','conf.lua'):shutil.copy2(root/'tests/jp30_camera_clearance_love'/name,app/name)
    for name in ('src','assets','data','tests'):(app/name).symlink_to(root/name,target_is_directory=True)
    env=dict(os.environ,JP_CLEAR_ROOT=str(root),JP_CLEAR_OUT=str(out),JP_CLEAR_BEFORE=str(a.before.resolve()),SDL_VIDEODRIVER='offscreen',LIBGL_ALWAYS_SOFTWARE='1',XDG_DATA_HOME=str(pathlib.Path(tmp)/'save'))
    r=subprocess.run([a.love,str(app)],env=env,text=True,stdout=subprocess.PIPE,stderr=subprocess.STDOUT)
    (out/'run.log').write_text(r.stdout);print(r.stdout,end='');raise SystemExit(r.returncode)
