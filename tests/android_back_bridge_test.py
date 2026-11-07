"""Compatibility entry point; contact and Back ownership now share one harness."""
import subprocess,sys,tempfile
from pathlib import Path
with tempfile.TemporaryDirectory(prefix='android-back-regression-')as output:
 subprocess.run([sys.executable,str(Path(__file__).with_name('android_back_gesture_test.py')),'--output',output],check=True)
