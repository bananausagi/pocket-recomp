"""Run production fullscreen methods with a small Android/SDL boundary.

Tests API gating and behavior ownership, not a physical Android gesture.
"""
from pathlib import Path
import subprocess
import tempfile

root = Path(__file__).resolve().parents[1]
activity = (root/'mobile/android/love/src/main/java/org/love2d/android/GameActivity.java').read_text()
start = activity.index('    private void allowFullscreenNavigation()')
end = activity.index('    @Override\n    public boolean dispatchKeyEvent', start)
methods = activity[start:end]
for method in ('onCreate', 'onResume'):
    pos = activity.index('void '+method+'(')
    body = activity[pos:activity.index('\n    }', pos)]
    assert 'allowFullscreenNavigation();' in body

stubs = {
 'android/os/Build.java': '''package android.os; public class Build {
  public static class VERSION { public static int SDK_INT=21; }}''',
 'android/view/WindowInsetsController.java': '''package android.view;
 public class WindowInsetsController {
  public static final int BEHAVIOR_DEFAULT=1; public boolean controlled=false;
  public boolean hidden=true; public int behavior=2,calls=0;
  public int getSystemBarsBehavior(){return controlled?behavior:BEHAVIOR_DEFAULT;}
  public void setSystemBarsBehavior(int value){controlled=true;behavior=value;calls++;}
 }''',
 'android/view/Window.java': '''package android.view; public class Window {
  public WindowInsetsController controller=new WindowInsetsController();
  public int reads=0; public WindowInsetsController getInsetsController(){
   if(android.os.Build.VERSION.SDK_INT<31)throw new AssertionError("unsupported API accessed");
   reads++;return controller;}
 }''',
 'org/libsdl/app/SDLActivity.java': '''package org.libsdl.app;
 import android.view.*;
 public class SDLActivity {
  public Window window=new Window();public int focusCalls=0,visibilityCalls=0;
  public Window getWindow(){return window;}
  public void onWindowFocusChanged(boolean focus){focusCalls++;}
  public void onSystemUiVisibilityChange(int visibility){visibilityCalls++;}
 }''',
}
main = '''
 private static int checks=0;
 static void check(boolean ok,String name){if(!ok)throw new AssertionError(name);checks++;System.out.println("PASS "+name);}
 public static void main(String[] args){
  for(int sdk:new int[]{21,30,31,33,36}){
   Build.VERSION.SDK_INT=sdk;GameActivity g=new GameActivity();
   WindowInsetsController c=g.window.controller;
   g.allowFullscreenNavigation();g.onWindowFocusChanged(true);g.onSystemUiVisibilityChange(0);
   check(g.focusCalls==1&&g.visibilityCalls==1,"API"+sdk+" retains SDL lifecycle callbacks");
   check(c.hidden,"API"+sdk+" keeps fullscreen bars hidden");
   if(sdk<31){check(g.window.reads==0&&!c.controlled,"API"+sdk+" never loads newer insets APIs");continue;}
   check(c.controlled&&c.behavior==1,"API"+sdk+" explicitly replaces unowned legacy sticky behavior");
   int calls=c.calls;g.onWindowFocusChanged(false);
   check(c.calls==calls,"API"+sdk+" focus loss does not change bar policy");
   c.behavior=2;g.onWindowFocusChanged(true);
   check(c.behavior==1,"API"+sdk+" focus regain restores direct navigation");
   c.behavior=2;g.onSystemUiVisibilityChange(4098);
   check(c.behavior==1,"API"+sdk+" SDL rehide callback retains direct navigation");
   g.window.controller=null;g.allowFullscreenNavigation();
   g.window=null;g.allowFullscreenNavigation();
   check(true,"API"+sdk+" tolerates unattached window/controller");
  }
  System.out.println(checks+" FULLSCREEN BOUNDARY CHECKS PASSED (+2 lifecycle checks)");
 }
'''
stubs['org/love2d/android/GameActivity.java'] = '''package org.love2d.android;
import org.libsdl.app.SDLActivity;import android.os.Build;import android.view.*;
public class GameActivity extends SDLActivity {
'''+methods+main+'\n}'
with tempfile.TemporaryDirectory(prefix='jp51-fullscreen-') as directory:
    temp = Path(directory)
    for name, body in stubs.items():
        path=temp/name;path.parent.mkdir(parents=True,exist_ok=True);path.write_text(body)
    subprocess.run(['java','com.sun.tools.javac.Main','-d',str(temp),*[str(temp/n) for n in stubs]],check=True)
    subprocess.run(['java','-cp',str(temp),'org.love2d.android.GameActivity'],check=True)
