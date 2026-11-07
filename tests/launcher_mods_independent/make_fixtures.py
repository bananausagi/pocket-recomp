import zipfile, json, pathlib, stat
root=pathlib.Path(__file__).parent/'fixtures'
root.mkdir(exist_ok=True)
m={'id':'qa_mod','name':'QA Mod','version':'1.0.0','entry':'main.lua','options_schema':'options.lua'}
def make(name,entries):
 with zipfile.ZipFile(root/name,'w',zipfile.ZIP_DEFLATED) as z:
  for path,data in entries: z.writestr(path,data)
def entries(version='1.0.0'):
 return [('mod/manifest.json',json.dumps(dict(m,version=version))),('mod/main.lua','return {}'),('mod/options.lua','-- only data\nreturn {{ key="toggle",type="toggle",default=true }}'),('mod/strings.lua','return {["Import ROM"]="ROMを読む"}')]
make('valid.zip',entries())
make('update.zip',entries('2.0.0'))
make('traversal.zip',entries()+[('../outside.lua','bad')])
make('case.zip',entries()+[('mod/MAIN.lua','bad')])
make('rom.zip',entries()+[('mod/baseroms/private.gb','bad')])
make('badmanifest.zip',[('manifest.json','{"id":"../escape"}'),('main.lua','return {}')])
make('missingentry.zip',[('manifest.json',json.dumps(dict(m,options_schema=None)))])
link=zipfile.ZipInfo('mod/link');link.create_system=3;link.external_attr=(stat.S_IFLNK|0o777)<<16
make('symlink.zip',entries()+[(link,'../../outside')])

make('dot.zip',[( './'+name,data) for name,data in entries()])
make('backslash.zip',[(name.replace('/',chr(92)),data) for name,data in entries()])
make('backslash-traversal.zip',entries()+[(r'..\outside.lua','bad')])
make('drive.zip',entries()+[('C:/outside.lua','bad')])
make('alias.zip',entries()+[('./mod/main.lua','bad')])
