"""Compile the production native locale selector and exercise every dialog pair.

A JVM locale boundary check; does not claim Android-device UI interaction.
"""
import json
import re
import subprocess
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
source = (ROOT/'mobile/android/love/src/main/java/org/love2d/android/GameActivity.java').read_text()
start=source.index('    private static String nativeUiText(')
end=source.index('\n    }',start)+len('\n    }')
method=source[start:end]
quoted=r'"(?:[^"\\]|\\.)*"'
pairs=re.findall(r'nativeUiText\(\s*('+quoted+r')\s*,\s*('+quoted+r')\s*\)',source)
assert len(pairs)==10, f'Unexpected native translation call count: {len(pairs)}'
rows=',\n'.join('{'+en+','+ja+'}' for en,ja in pairs)
program='''import java.util.Locale;
public class NativeLocaleFixture {
METHOD
public static void main(String[] args) {
 Locale previous=Locale.getDefault();int checks=0;
 String[][] pairs={PAIRS};
 try {
  Locale[] locales={Locale.JAPANESE,Locale.JAPAN,Locale.US,Locale.FRANCE,new Locale("ja","US")};
  for(Locale locale:locales){
   Locale.setDefault(locale);
   boolean japanese="ja".equals(locale.getLanguage());
   for(String[] pair:pairs){
    String actual=nativeUiText(pair[0],pair[1]);
    if(!actual.equals(pair[japanese?1:0]))throw new AssertionError(locale+": "+actual);
    checks++;
   }
  }
  for(Locale locale:new Locale[]{Locale.JAPAN,Locale.US}){
   Locale.setDefault(locale);
   String message=String.format(nativeUiText(pairs[0][0],pairs[0][1]),"/空白 100% game.love","ftp");
   if(!message.contains("/空白 100% game.love")||!message.contains("ftp"))throw new AssertionError(message);
   checks++;
  }
 } finally {Locale.setDefault(previous);}
 System.out.println("PASS "+checks+" native locale checks (all 10 production dialog/chooser calls)");
}
}
'''.replace('METHOD',method).replace('PAIRS',rows)
with tempfile.TemporaryDirectory(prefix='kanto-native-locale-') as temp:
    stage=Path(temp);(stage/'NativeLocaleFixture.java').write_text(program)
    subprocess.run(['java','com.sun.tools.javac.Main','-encoding','UTF-8','-d',str(stage),str(stage/'NativeLocaleFixture.java')],check=True)
    subprocess.run(['java','-cp',str(stage),'NativeLocaleFixture'],check=True)
