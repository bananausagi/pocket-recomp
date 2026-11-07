#!/usr/bin/env python3
"""Run the actual threaded revision-metadata path with synthetic bytes."""
import argparse
import os
from pathlib import Path
import shutil
import subprocess
import tempfile

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--love", default="love")
parser.add_argument("--output", type=Path, required=True)
args = parser.parse_args()
root = Path(__file__).resolve().parents[2]
out = args.output.resolve()
out.mkdir(parents=True, exist_ok=True)
with tempfile.TemporaryDirectory(prefix="jp-revision-qa-") as temporary:
    app = Path(temporary) / "app"
    app.mkdir()
    for name in ["main.lua", "conf.lua"]:
        shutil.copy2(Path(__file__).parent / name, app / name)
    for name in ["src", "assets", "data", "tools", "tests"]:
        (app / name).symlink_to(root / name, target_is_directory=True)
    env = dict(os.environ, JP_REVISION_OUT=str(out), SDL_VIDEODRIVER="offscreen",
               LIBGL_ALWAYS_SOFTWARE="1", ALSOFT_DRIVERS="null",
               XDG_DATA_HOME=str(Path(temporary) / "save"))
    lib = Path(args.love).resolve().parent.parent / "lib"
    if lib.is_dir():
        env["LD_LIBRARY_PATH"] = str(lib) + os.pathsep + env.get("LD_LIBRARY_PATH", "")
    result = subprocess.run([args.love, str(app)], env=env, text=True,
                            stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    (out / "actual-worker.log").write_text(result.stdout)
    print(result.stdout, end="")
    raise SystemExit(result.returncode)
