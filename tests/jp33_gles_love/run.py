#!/usr/bin/env python3
"""Run the exact jp.32 regression and current rendering on real ES 2 and ES 3.

Requires LÖVE 11.5, Mesa/EGL and libGLESv2. Each fixture asserts the actual
renderer and major version, so desktop GL fallback cannot count as success.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
from zipfile import ZipFile

ROOT=Path(__file__).resolve().parents[2]
BASE_SOURCE='3155a05ee5a37a0e4502402e29c6454a43c45527c1c6d011cc9b329d35fdf16e'

def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('--love',required=True)
    p.add_argument('--jp32-source',type=Path,required=True)
    p.add_argument('--output',type=Path,required=True)
    p.add_argument('--phases',nargs='+',choices=['shader','effects','world','battle'],
                   default=['shader','effects','world','battle'])
    a=p.parse_args();out=a.output.resolve();out.mkdir(parents=True,exist_ok=True)
    assert hashlib.sha256(a.jp32_source.read_bytes()).hexdigest()==BASE_SOURCE
    results={}
    with tempfile.TemporaryDirectory(prefix='jp33-gles-')as tmp:
        stage=Path(tmp);app=stage/'app';app.mkdir()
        for name in ('main.lua','conf.lua'):
            shutil.copy2(ROOT/'tests/jp33_gles_love'/name,app/name)
        before=stage/'jp32-Voxel3D.lua'
        with ZipFile(a.jp32_source)as z:
            before.write_bytes(z.read('source/vendor/jp-mods/DRAMALESS_SHAPE/lib/Voxel3D.lua'))
        for major in (2,3):
            env=dict(os.environ,LOVE_GRAPHICS_USE_OPENGLES='1',
                LOVE_GRAPHICS_USE_GL2='1' if major==2 else '0',
                MESA_GLES_VERSION_OVERRIDE='2.0' if major==2 else '3.0',
                JP_QA_REQUIRE_GLES=str(major),JP_QA_EMULATE_ANDROID='1',
                SDL_VIDEODRIVER='offscreen',LIBGL_ALWAYS_SOFTWARE='1',ALSOFT_DRIVERS='null',
                JP_SHADER_ROOT=str(ROOT),JP_SHADER_BEFORE=str(before),
                XDG_DATA_HOME=str(stage/('data-es'+str(major))))
            for phase in a.phases:
                label=f'es{major}-{phase}';dest=out/label;dest.mkdir(exist_ok=True)
                env['JP_SHADER_OUT']=str(dest)
                # The maintained battle fixture covers the current camera,
                # native effects and HUD in the mobile usable viewport.
                env['JP_QA_ACTION_CAMERA']='1' if phase=='battle' else '0'
                if phase=='shader':command=[a.love,str(app)]
                elif phase=='effects':
                    command=[sys.executable,str(ROOT/'tests/jp32_effects_love/run.py'),
                             '--love',a.love,'--output',str(dest)]
                else:
                    command=[sys.executable,str(ROOT/'tools/run_jp_display_qa.py'),
                             '--love',a.love,'--output',str(dest),
                             '--free-camera' if phase=='world' else '--battle-ui']
                r=subprocess.run(command,cwd=ROOT,env=env,text=True,capture_output=True,timeout=180)
                log=r.stdout+r.stderr;(dest/'driver.log').write_text(log)
                results[label]={'exitCode':r.returncode,'summary':log.strip().splitlines()[-1:]}
                print(label,r.returncode,*results[label]['summary'],flush=True)
                if r.returncode:print('\n'.join(log.splitlines()[-25:]),flush=True)
    (out/'matrix.json').write_text(json.dumps({'jp32SourceSHA256':BASE_SOURCE,
        'cases':results,'romUsed':False,'androidDeviceUsed':False},indent=2)+'\n')
    raise SystemExit(int(any(r['exitCode']for r in results.values())))

if __name__=='__main__':main()
