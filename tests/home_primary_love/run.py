#!/usr/bin/env python3
"""Focused real-GL home action checks, without a ROM or existing user saves."""
import argparse, os, pathlib, shutil, subprocess, tempfile
p=argparse.ArgumentParser(description=__doc__)
p.add_argument('--love',default='love')
p.add_argument('--output',type=pathlib.Path,required=True)
p.add_argument('--source',type=pathlib.Path)
p.add_argument('--before',action='store_true')
a=p.parse_args();fixture=pathlib.Path(__file__).resolve().parent
root=(a.source or fixture.parents[1]).resolve()
out=a.output.resolve();out.mkdir(parents=True,exist_ok=True)
with tempfile.TemporaryDirectory(prefix='jp-home-primary-') as tmp:
    app=pathlib.Path(tmp)/'app';app.mkdir()
    for name in ('main.lua','conf.lua'): shutil.copy2(fixture/name,app/name)
    for name in ('src','assets','data','tests','tools'):
        (app/name).symlink_to(root/name,target_is_directory=True)
    shutil.copy2(root/'LICENSE.MD',app/'LICENSE.MD')
    env=dict(os.environ,JP_HOME_ROOT=str(root),JP_HOME_OUT=str(out),
        JP_HOME_BEFORE='1' if a.before else '0',
        SDL_VIDEODRIVER='offscreen',LIBGL_ALWAYS_SOFTWARE='1',ALSOFT_DRIVERS='null',
        XDG_DATA_HOME=str(pathlib.Path(tmp)/'save'))
    result=subprocess.run([a.love,str(app)],env=env,text=True,stdout=subprocess.PIPE,stderr=subprocess.STDOUT)
    (out/'run.log').write_text(result.stdout);print(result.stdout,end='')
    raise SystemExit(result.returncode)
