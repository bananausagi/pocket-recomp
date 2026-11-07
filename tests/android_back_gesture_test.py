"""Production GameActivity + SDL onTouch, simulated Android framework boundary.

Writes the actual JNI event stream for replay through main.lua. No device claim.
--baseline-source extracts the delivered jp.52 Java methods without modifying them.
"""
import argparse, json, subprocess, tempfile
from pathlib import Path
from zipfile import ZipFile
ROOT=Path(__file__).resolve().parents[1]
p=argparse.ArgumentParser();p.add_argument('--output',type=Path,required=True);p.add_argument('--baseline-source',type=Path)
a=p.parse_args();a.output.mkdir(parents=True,exist_ok=True)
import xml.etree.ElementTree as ET
rel='mobile/android/love/src/main/java/org/love2d/android/GameActivity.java'
if a.baseline_source:
 with ZipFile(a.baseline_source)as z:activity=z.read('source/'+rel).decode()
else:activity=(ROOT/rel).read_text()
i=activity.index('    @Override\n    protected org.libsdl.app.SDLSurface createSDLSurface')
surface=activity[i:activity.index('    @Override\n    protected void onCreate',i)]
i=activity.index('    @Override\n    public boolean dispatchKeyEvent(KeyEvent event)')
back=activity[i:activity.index('    /**',activity.index('private static final class NavigationBackApi33',i))]
for method,hook in [('onResume','registerNavigationBack();'),('onPause','unregisterNavigationBack();'),('onDestroy','unregisterNavigationBack();')]:
 pos=activity.index('void '+method+'(');body=activity[pos:activity.index('\n    }',pos)]
 assert hook in body,method
ns='{http://schemas.android.com/apk/res/android}'
manifest=ET.parse(ROOT/'mobile/android/app/src/main/AndroidManifest.xml')
entry=next(e for e in manifest.findall('./application/activity')if e.get(ns+'name')=='org.love2d.android.GameActivity')
assert entry.get(ns+'enableOnBackInvokedCallback')=='true'
sdl=(ROOT/'mobile/android/love/src/jni/SDL2/android-project/app/src/main/java/org/libsdl/app/SDLSurface.java').read_text()
i=sdl.index('    @Override\n    public boolean onTouch(View v, MotionEvent event)')
sdl=sdl[i:sdl.index('    // Sensor events',i)]
files={
'android/content/Context.java':'package android.content;public class Context {}',
'android/os/Build.java':'package android.os;public class Build {public static class VERSION {public static int SDK_INT=36;}}',
'android/view/View.java':'''package android.view;public class View {public interface OnTouchListener {boolean onTouch(View v,MotionEvent e);}}''',
'android/view/InputDevice.java':'package android.view;public class InputDevice {public static final int SOURCE_MOUSE=8194,SOURCE_TOUCHSCREEN=4098;}',
'android/view/KeyCharacterMap.java':'package android.view;public class KeyCharacterMap {public static final int VIRTUAL_KEYBOARD=-1;}',
'android/view/KeyEvent.java':'''package android.view;public class KeyEvent {
 public static final int KEYCODE_BACK=4,KEYCODE_SHIFT_RIGHT=60,ACTION_DOWN=0,ACTION_UP=1;
 public int key=4,action,device;public boolean cancel;
 public KeyEvent(int a,int d){action=a;device=d;}
 public int getKeyCode(){return key;}public int getAction(){return action;}
 public int getDeviceId(){return device;}public boolean isCanceled(){return cancel;}
}''',
'android/view/MotionEvent.java':'''package android.view;public class MotionEvent {
 public static final int ACTION_DOWN=0,ACTION_UP=1,ACTION_MOVE=2,ACTION_CANCEL=3,ACTION_POINTER_DOWN=5,ACTION_POINTER_UP=6,FLAG_CANCELED=32;
 public int action,source=4098,device=7,flags,index;public long time;public int[] ids={1};public float[] xs={220},ys={210};
 public MotionEvent(int a,long t){action=a;time=t;} public static MotionEvent obtain(MotionEvent e){
  MotionEvent n=new MotionEvent(e.action,e.time);n.source=e.source;n.device=e.device;n.flags=e.flags;n.index=e.index;
  n.ids=e.ids.clone();n.xs=e.xs.clone();n.ys=e.ys.clone();return n;}
 public void recycle(){}public int getSource(){return source;}public int getActionMasked(){return action;}
 public long getDownTime(){return time;}public int getDeviceId(){return device;}public int getFlags(){return flags;}
 public int getPointerCount(){return ids.length;}public int getPointerId(int i){return ids[i];}public int getActionIndex(){return index;}
 public float getX(int i){return xs[i];}public float getY(int i){return ys[i];}public float getPressure(int i){return action==1?0:1;}
 public int getButtonState(){return 1;}
}''',
'android/window/BackEvent.java':'package android.window;public class BackEvent {}',
'android/window/OnBackInvokedCallback.java':'package android.window;public interface OnBackInvokedCallback {void onBackInvoked();}',
'android/window/OnBackAnimationCallback.java':'''package android.window;public interface OnBackAnimationCallback extends OnBackInvokedCallback {
 default void onBackStarted(BackEvent e){}default void onBackProgressed(BackEvent e){}default void onBackCancelled(){}
}''',
'android/window/OnBackInvokedDispatcher.java':'''package android.window;public class OnBackInvokedDispatcher {
 public static final int PRIORITY_DEFAULT=0;public int added,removed,priority;public OnBackInvokedCallback callback;
 public void registerOnBackInvokedCallback(int p,OnBackInvokedCallback c){added++;priority=p;callback=c;}
 public void unregisterOnBackInvokedCallback(OnBackInvokedCallback c){if(c!=callback)throw new AssertionError();removed++;callback=null;}
}''',
'org/libsdl/app/SDLGenericMotionListener_API12.java':'''package org.libsdl.app;import android.view.*;
 public class SDLGenericMotionListener_API12 {public float getEventX(MotionEvent e){return e.getX(0);}public float getEventY(MotionEvent e){return e.getY(0);}public boolean inRelativeMode(){return false;}}''',
'org/libsdl/app/SDLSurface.java':'''package org.libsdl.app;import android.view.*;import android.content.*;
 public class SDLSurface implements View.OnTouchListener {protected float mWidth=480,mHeight=800;public SDLSurface(Context c){}
'''+sdl+'}',
'org/libsdl/app/SDLActivity.java':'''package org.libsdl.app;import android.view.*;import android.content.*;import android.window.*;import java.util.*;
 public class SDLActivity {
 public static boolean mBrokenLibraries;protected static Thread mSDLThread=new Thread();public boolean finishing;
 public static List<String> events=new ArrayList<>();public static int otherKeys,mouseEvents,lastDevice;
 public final OnBackInvokedDispatcher dispatcher=new OnBackInvokedDispatcher();
 protected SDLSurface createSDLSurface(Context c){return new SDLSurface(c);}
 public static void onNativeTouch(int d,int id,int a,float x,float y,float p){lastDevice=d;events.add("touch,"+id+","+a+","+x+","+y+","+p);}
 public static void onNativeKeyDown(int k){events.add("keydown,"+k);}public static void onNativeKeyUp(int k){events.add("keyup,"+k);}
 public static void onNativeMouse(int b,int a,float x,float y,boolean r){mouseEvents++;}
 public static SDLGenericMotionListener_API12 getMotionListener(){return new SDLGenericMotionListener_API12();}
 public boolean dispatchKeyEvent(KeyEvent e){otherKeys++;return false;}public void onBackPressed(){throw new AssertionError("system exit");}
 public boolean isFinishing(){return finishing;}public OnBackInvokedDispatcher getOnBackInvokedDispatcher(){return dispatcher;}
 }'''
}
main=r'''
 static int checks;static java.util.List<String> failures=new java.util.ArrayList<>();
 static void check(boolean ok,String label){checks++;if(!ok)failures.add(label);System.out.println((ok?"PASS ":"FAIL ")+label);}
 static void start(GameActivity g){if(g.dispatcher.callback instanceof android.window.OnBackAnimationCallback)
  ((android.window.OnBackAnimationCallback)g.dispatcher.callback).onBackStarted(new android.window.BackEvent());}
 static void cancel(GameActivity g){if(g.dispatcher.callback instanceof android.window.OnBackAnimationCallback)
  ((android.window.OnBackAnimationCallback)g.dispatcher.callback).onBackCancelled();}
 static void touch(org.libsdl.app.SDLSurface s,int action,long time){s.onTouch(new View(),new MotionEvent(action,time));}
 static long backs(){return events.stream().filter(e->e.equals("keydown,4")).count();}
 static long taps(){return events.stream().filter(e->e.startsWith("touch,")&&e.split(",")[2].equals("1")&&Float.parseFloat(e.split(",")[5])>=0).count();}
 static long cancels(){return events.stream().filter(e->e.endsWith(",-1.0")).count();}
 static void trace(String name){for(String event:events)System.out.println("TRACE "+name+" "+event);}
 public static void main(String[] args){
  GameActivity g=new GameActivity();org.libsdl.app.SDLSurface s=g.createSDLSurface(new Context());g.registerNavigationBack();
  check(g.dispatcher.callback instanceof android.window.OnBackAnimationCallback,"API34+ registers gesture lifecycle callback");
  touch(s,0,100);start(g);touch(s,1,100);events.add("tick");g.dispatcher.callback.onBackInvoked();events.add("tick");
  trace("claimed-up-before-back");check(taps()==0&&cancels()==1&&backs()==1,"claimed gesture UP before commit cancels touch and produces only Back");
  events.clear();touch(s,0,200);start(g);cancel(g);touch(s,1,200);events.add("tick");trace("abandoned-gesture");
  check(taps()==0&&backs()==0,"abandoned gesture never turns into a tap");
  events.clear();touch(s,0,201);touch(s,1,201);events.add("tick");trace("next-real-tap");check(taps()==1,"next distinct contact works immediately");
  events.clear();touch(s,0,300);start(g);g.dispatchKeyEvent(new KeyEvent(0,-1));g.dispatchKeyEvent(new KeyEvent(1,-1));
  g.dispatcher.callback.onBackInvoked();events.add("tick");g.onBackPressed();events.add("tick");
  trace("legacy-echo");check(backs()==1,"modern gesture plus legacy echoes produces only one Back");
  events.clear();start(g);touch(s,0,400);touch(s,1,400);g.dispatcher.callback.onBackInvoked();touch(s,2,400);touch(s,1,400);
  check(taps()==0&&events.size()==2,"contacts delivered after gesture claim or commit cannot start another touch");
  events.clear();touch(s,0,500);start(g);g.dispatcher.callback.onBackInvoked();touch(s,3,500);touch(s,1,500);
  check(cancels()==1&&backs()==1&&taps()==0,"Back before delayed CANCEL cleans each native finger once");
  events.clear();touch(s,0,600);start(g);cancel(g);touch(s,2,600);touch(s,1,600);
  check(cancels()==1&&taps()==0&&backs()==0,"late MOVE after abandoned gesture stays cancelled");
  events.clear();touch(s,0,700);MotionEvent multi=new MotionEvent(5,700);multi.ids=new int[]{1,9};multi.xs=new float[]{220,320};multi.ys=new float[]{210,250};multi.index=1;s.onTouch(new View(),multi);start(g);g.dispatcher.callback.onBackInvoked();
  check(cancels()==2&&backs()==1,"gesture start retires all tracked fingers");
  events.clear();touch(s,0,800);MotionEvent flagged=new MotionEvent(1,800);flagged.flags=MotionEvent.FLAG_CANCELED;s.onTouch(new View(),flagged);
  check(cancels()==1&&taps()==0,"flagged UP is cancellation");
  events.clear();touch(s,0,850);flagged=new MotionEvent(6,850);flagged.flags=MotionEvent.FLAG_CANCELED;s.onTouch(new View(),flagged);touch(s,2,850);touch(s,1,850);
  check(cancels()==1&&taps()==0,"flagged POINTER_UP cannot restart a contact");
  events.clear();touch(s,0,900);start(g);g.unregisterNavigationBack();touch(s,1,900);g.registerNavigationBack();touch(s,0,901);touch(s,1,901);
  check(taps()==1&&backs()==0,"pause releases ownership and next real tap remains usable");
  events.clear();touch(s,0,1000);touch(s,3,1000);touch(s,1,1000);
  check(cancels()==1&&taps()==0,"ordinary OS CANCEL still has no later tap");
  events.clear();touch(s,0,1100);g.dispatcher.callback.onBackInvoked();touch(s,1,1100);g.dispatcher.callback.onBackInvoked();
  check(cancels()==1&&taps()==0&&backs()==2,"button/accessibility invocations without start remain repeatable");
  events.clear();for(int i=0;i<2;i++){start(g);g.dispatcher.callback.onBackInvoked();}
  check(backs()==2,"two distinct rapid gestures are both accepted");
  events.clear();g.dispatchKeyEvent(new KeyEvent(0,8));g.dispatchKeyEvent(new KeyEvent(1,8));check(backs()==1,"physical Back remains available");
  events.clear();KeyEvent other=new KeyEvent(0,8);other.key=24;check(!g.dispatchKeyEvent(other)&&otherKeys==1,"unrelated key retains normal dispatch");
  for(int source:new int[]{8194,12290}){start(g);MotionEvent mouse=new MotionEvent(0,1200);mouse.source=source;int before=mouseEvents;s.onTouch(new View(),mouse);check(mouseEvents==before+1,"mouse/DeX is not suppressed "+source);cancel(g);}
  g.unregisterNavigationBack();Build.VERSION.SDK_INT=33;g.registerNavigationBack();events.clear();touch(s,0,1300);g.dispatcher.callback.onBackInvoked();touch(s,1,1300);
  check(cancels()==1&&taps()==0&&backs()==1,"API33 commit cancels active contact before Back");
  g.unregisterNavigationBack();Build.VERSION.SDK_INT=21;g.registerNavigationBack();events.clear();touch(s,0,1400);g.dispatchKeyEvent(new KeyEvent(1,-1));touch(s,1,1400);
  check(cancels()==1&&taps()==0&&backs()==1,"legacy key cancels active contact before Back");
  events.clear();g.onBackPressed();check(backs()==1,"legacy onBackPressed still works without dispatcher");

  events.clear();g.dispatchKeyEvent(new KeyEvent(0,-1));g.dispatchKeyEvent(new KeyEvent(0,-1));
  check(backs()==0,"held or repeating legacy Back waits for release");
  KeyEvent cancelledKey=new KeyEvent(1,-1);cancelledKey.cancel=true;g.dispatchKeyEvent(cancelledKey);check(backs()==0,"cancelled legacy key does not navigate");
  mBrokenLibraries=true;g.onBackPressed();mBrokenLibraries=false;check(backs()==0,"failed native startup never invokes JNI");
  mSDLThread=null;g.onBackPressed();mSDLThread=new Thread();check(backs()==0,"missing SDL thread never invokes JNI");
  g.finishing=true;g.onBackPressed();g.finishing=false;check(backs()==0,"finishing Activity never invokes JNI");
  for(int sdk:new int[]{33,34,36,37}){
   Build.VERSION.SDK_INT=sdk;int added=g.dispatcher.added,removed=g.dispatcher.removed;
   g.registerNavigationBack();g.registerNavigationBack();
   check(g.dispatcher.added==added+1&&g.dispatcher.priority==0,"one DEFAULT-priority callback on API"+sdk);
   g.unregisterNavigationBack();g.unregisterNavigationBack();check(g.dispatcher.removed==removed+1,"unregister is idempotent on API"+sdk);
  }
  events.clear();MotionEvent negative=new MotionEvent(0,1500);negative.device=-1;s.onTouch(new View(),negative);
  negative.action=3;s.onTouch(new View(),negative);check(cancels()==1&&taps()==0&&lastDevice==-2,"negative device id avoids SDL reserved id");
  String[] c=events.get(events.size()-1).split(",");check(c[1].equals("1")&&Math.abs(Float.parseFloat(c[3])-220f/480)<1e-6&&Math.abs(Float.parseFloat(c[4])-210f/800)<1e-6,"cancel retains finger identity and normalized position");
  events.clear();touch(s,2,1501);touch(s,1,1501);check(events.isEmpty(),"orphan MOVE/UP cannot invent a tap");
  events.clear();touch(s,0,1600);touch(s,0,1600);touch(s,0,1601);touch(s,1,1600);touch(s,1,1601);
  check(cancels()==1&&taps()==1&&events.size()==4,"new contact cancels lost old stream; duplicate DOWN and old UP cannot act");
  System.out.println("RESULT "+checks+" "+failures.size());
  if(!failures.isEmpty())System.exit(1);
 }
'''
files['org/love2d/android/GameActivity.java']='''package org.love2d.android;
import org.libsdl.app.SDLActivity;import android.view.*;import android.content.*;import android.os.Build;
public class GameActivity extends SDLActivity {
 private Object navigationBackCallback;private CancelAwareSurface navigationSurface;
 private boolean secondaryEnabled;private int dualScreenDisplayMode=-1;
'''+surface+back+main+'}'
with tempfile.TemporaryDirectory(prefix='jp53-native-input-')as temp:
 temp=Path(temp)
 for name,body in files.items():
  path=temp/name;path.parent.mkdir(parents=True,exist_ok=True);path.write_text(body)
 r=subprocess.run(['java','com.sun.tools.javac.Main','-d',str(temp),*[str(temp/n)for n in files]],capture_output=True,text=True)
 (a.output/'compile.log').write_text(r.stdout+r.stderr)
 if r.returncode:print(r.stderr);raise SystemExit(r.returncode)
 r=subprocess.run(['java','-cp',str(temp),'org.love2d.android.GameActivity'],capture_output=True,text=True)
 (a.output/'java.log').write_text(r.stdout+r.stderr)
 traces={}
 for line in r.stdout.splitlines():
  if line.startswith('TRACE '):
   _,scenario,event=line.split(' ',2);traces.setdefault(scenario,[]).append(event.split(','))
  else:print(line)
 (a.output/'jni-traces.json').write_text(json.dumps(traces,indent=2)+'\n')
 raise SystemExit(r.returncode)
