#!/usr/bin/env python3
"""Render app menus at real physical sizes with isolated settings and no ROM."""
import argparse, json, os, pathlib, shutil, subprocess, tempfile
p=argparse.ArgumentParser(description=__doc__)
p.add_argument('--love',default='love')
p.add_argument('--output',type=pathlib.Path,required=True)
p.add_argument('--before',action='store_true')
p.add_argument('--source',type=pathlib.Path,help='Immutable source tree for a before comparison')
a=p.parse_args();fixture_root=pathlib.Path(__file__).resolve().parents[2]
root=a.source.resolve() if a.source else fixture_root
out=a.output.resolve();out.mkdir(parents=True,exist_ok=True)
with tempfile.TemporaryDirectory(prefix='jp-readable-ui-') as tmp:
    app=pathlib.Path(tmp)/'app';app.mkdir()
    for name in ('main.lua','conf.lua'):
        shutil.copy2(fixture_root/'tests/readable_launcher_love'/name,app/name)
    for name in ('src','assets','data','tests','tools'):
        (app/name).symlink_to(root/name,target_is_directory=True)
    shutil.copy2(root/'LICENSE.MD',app/'LICENSE.MD')
    env=dict(os.environ,JP_READABLE_ROOT=str(root),JP_READABLE_OUT=str(out),
             JP_READABLE_BEFORE='1' if a.before else '0',SDL_VIDEODRIVER='offscreen',
             LIBGL_ALWAYS_SOFTWARE='1',ALSOFT_DRIVERS='null',XDG_DATA_HOME=str(pathlib.Path(tmp)/'save'))
    r=subprocess.run([a.love,str(app)],env=env,text=True,stdout=subprocess.PIPE,stderr=subprocess.STDOUT)
    (out/'run.log').write_text(r.stdout);print(r.stdout,end='')
    raise SystemExit(r.returncode)
