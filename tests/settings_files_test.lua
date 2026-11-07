-- Picker/controller lifecycle only; JSON/schema correctness belongs to the
-- SettingsTransfer suite. Simulates existing native basename import/export.
package.path="./?.lua;./?/init.lua;"..package.path
local T=require("tests.harness")
local realLove=love
local realCodec=package.loaded["src.import.SettingsTransfer"]
local PICK="picked_settings.json"
local fs,reads,removed,picks,notices,applied,options,Files,writeFail,readFail,applyFail
local function reset(osName)
  fs,reads,removed,picks,notices,applied={},{},{},{},{},{}
  writeFail,readFail,applyFail=nil,nil,nil
  options={musicVol=3,private="keep"}
  love={system={getOS=function()return osName or "Android"end,
    pickFile=function(kind,dest)picks[#picks+1]={kind,dest};return true end,
    createFile=function(name)picks[#picks+1]={"export",name};return true end},filesystem={}}
  function love.filesystem.getInfo(p)if fs[p]~=nil then return{type="file",size=#fs[p]}end end
  function love.filesystem.read(p)reads[p]=(reads[p]or 0)+1;if p==readFail then return nil,"fixture failure"end;return fs[p]end
  function love.filesystem.write(p,b)if p==writeFail then fs[p]="partial";return false,"fixture failure"end;fs[p]=b;return true end
  function love.filesystem.remove(p)removed[#removed+1]=p;fs[p]=nil;return true end
  function love.filesystem.createDirectory()return true end
  function love.filesystem.getSaveDirectory()return"/test-save"end
  package.loaded["src.import.SettingsTransfer"]={MAX_BYTES=32,
    import=function(bytes,base)
      if bytes~="good"then return nil,"invalid fixture"end
      return{musicVol=6,private=base.private}
    end,export=function()return"export fixture"end}
  package.loaded["src.import.SettingsFiles"]=nil
  Files=require("src.import.SettingsFiles")
end
local function hooks()
  return{apply=function(candidate)
    applied[#applied+1]=candidate
    if applyFail then return false,"write failed"end
    options=candidate;return true
  end,notify=function(text,ok)notices[#notices+1]={text=text,ok=ok}end}
end
local function finishPick(bytes)
  fs[PICK]=bytes;Files.focus(false);Files.focus(true);return Files.update(0)
end

reset();fs[PICK]="stale";fs["picked_mod.zip"]="foreign";fs["picked_rom.gb"]="foreign ROM"
T.check(Files.import(options,hooks()),"Android import opens")
T.eq(picks[1][1],"required_import","uses existing generic native picker")
T.eq(picks[1][2],PICK,"picker receives dedicated JSON basename")
T.eq(fs[PICK],nil,"own stale payload is cleared")
T.eq(fs["picked_mod.zip"],"foreign","MOD staging is untouched")
T.eq(fs["picked_rom.gb"],"foreign ROM","ROM staging is untouched")
T.check(Files.update(0.1),"pending picker holds main update paused")
T.check(not Files.import(options,hooks()),"second import cannot overlap pending operation")
T.check(not Files.export(options,hooks()),"export cannot overlap pending import")
T.check(not finishPick("good"),"successful picker releases update gate")
T.eq(#applied,1,"completed import applies once")
T.eq(options.musicVol,6,"candidate settings applied")
T.eq(options.private,"keep","existing private options are passed through codec")
T.eq(fs[PICK],nil,"consumed JSON staging is removed")
Files.update(10);T.eq(#applied,1,"subsequent frames cannot reapply payload")

reset();Files.import(options,hooks());Files.focus(false);fs[PICK]="part"
T.check(Files.update(0.1),"partial native copy keeps update gate held")
T.eq(reads[PICK]or 0,0,"native basename body is not read before focus returns")
T.eq(#applied,0,"native partial copy is never applied")
T.eq(fs[PICK],"part","pending native copy is not deleted")
fs[PICK]="good"
T.check(Files.update(5),"finished native bytes still wait for picker focus return")
T.eq(#applied,0,"native focus gate cannot time out while picker is open")
Files.focus(true);T.check(not Files.update(0),"focus return permits completed native copy")
T.eq(#applied,1,"native complete copy applies exactly once after focus return")
Files.focus(true);Files.update(1);T.eq(#applied,1,"duplicate focus events cannot reapply settings")

reset();fs["pick_error.flag"]=PICK;fs["pick_complete.flag"]="v1\n"..PICK.."\nold\n1\n"
Files.import(options,hooks())
T.eq(fs["pick_error.flag"],nil,"own old error flag is cleared before new picker")
T.eq(fs["pick_complete.flag"],nil,"own old completion is cleared before new picker")
T.check(Files.update(0),"stale own failure cannot kill new request")
fs["pick_error.flag"]=PICK
T.check(not Files.update(0),"current own error finishes request")
T.eq(#applied,0,"failed native read never applies")
T.eq(fs["pick_error.flag"],nil,"handled own error removed")

reset();fs["pick_error.flag"]="mods/something/picked_settings.json";fs["pick_complete.flag"]="v1\nmods/something/picked_settings.json\nx\n4\n"
Files.import(options,hooks())
T.check(Files.update(0),"foreign path containing our filename is not our failure")
finishPick("good")
T.check(fs["pick_error.flag"]~=nil,"foreign error flag remains")
T.check(fs["pick_complete.flag"]~=nil,"foreign completion marker remains")

reset();Files.import(options,hooks());Files.focus(false);Files.focus(true)
T.check(Files.update(0.25),"focus cancellation grace tolerates delayed native result")
T.check(not Files.update(0.3),"cancelled picker eventually releases update")
T.check(not Files.pending(),"cancel clears pending job")
T.eq(#applied,0,"cancel cannot mutate settings")

reset();Files.import(options,hooks());finishPick(string.rep("x",33))
T.eq(reads[PICK]or 0,0,"oversize file rejected before reading body")
T.eq(#applied,0,"oversize never applies")
T.eq(fs[PICK],nil,"rejected own large staging removed")
reset();readFail=PICK;Files.import(options,hooks());finishPick("good")
T.eq(#applied,0,"filesystem read failure never applies")
T.eq(fs[PICK],nil,"failed own staging cleaned")
reset();applyFail=true;Files.import(options,hooks());finishPick("good")
T.eq(options.musicVol,3,"rejected persistence keeps previous options")
T.check(not notices[#notices].ok,"persistence failure reports error")
T.check(not Files.pending(),"persistence failure releases pending job")

reset();T.check(Files.export(options,hooks()),"Android export opens save picker")
T.eq(fs["pending_export.sav"],"export fixture","native export staging has encoded settings")
T.eq(picks[1][2],"kanto-player-settings.json","save picker suggests JSON extension")
T.check(Files.update(0.1),"export remains pending while native chooser is open")
fs["export_done.flag"]="ok";fs["export_result.flag"]="v1\nkanto-player-settings.json\nok\n"
T.check(not Files.update(0),"native result finishes export")
T.eq(fs["pending_export.sav"],nil,"successful export removes own staging")
T.eq(fs["export_done.flag"],nil,"successful export consumes done marker")
T.check(notices[#notices].ok,"export success reported")
reset();writeFail="pending_export.sav"
T.check(not Files.export(options,hooks()),"native export write failure does not open picker")
T.eq(#picks,0,"failed staging never invokes SAF")
T.eq(fs["pending_export.sav"],nil,"partial failed export staging is removed")
reset();fs["pending_export.sav"]="foreign save";fs["export_done.flag"]="foreign result"
T.check(not Files.export(options,hooks()),"foreign pending export is protected")
T.eq(fs["pending_export.sav"],"foreign save","foreign export bytes remain intact")
T.eq(fs["export_done.flag"],"foreign result","foreign export completion remains intact")
reset();love.system.createFile=function()return false end
T.check(not Files.export(options,hooks()),"unavailable create picker fails cleanly")
T.eq(fs["pending_export.sav"],nil,"picker-open failure removes own export staging")
reset();Files.export(options,hooks());Files.focus(false);Files.focus(true);Files.update(0.6)
T.check(Files.pending(),"focus alone cannot cancel a document export")
fs["export_result.flag"]="v1\nkanto-player-settings.json\ncancelled\n";Files.update(0)
T.eq(fs["pending_export.sav"],nil,"cancelled export removes own staging")
T.check(not Files.pending(),"cancelled export clears pending")

local function dropped(name,bytes,opts)
  opts=opts or{};local handle={closed=0}
  function handle:getFilename()return name end
  function handle:open()return not opts.openFail end
  function handle:getSize()return opts.size or #bytes end
  function handle:read()if opts.readThrows then error("read error")end;return bytes end
  function handle:close()self.closed=self.closed+1 end
  return handle
end
reset("Linux");Files.import(options,hooks())
T.check(Files.pending(),"desktop import waits for drop")
T.eq(#picks,0,"desktop drop flow uses no Android API")
T.check(not Files.filedropped(dropped("other.zip","good")),"non-JSON drop is not mistaken for settings")
local file=dropped("config.JSON","good")
T.check(Files.filedropped(file),"JSON drop reaches controller")
T.eq(#applied,1,"desktop valid drop applies once")
T.eq(file.closed,1,"desktop drop handle closes")
T.check(not Files.pending(),"successful drop clears pending")
reset("Linux");Files.import(options,hooks());T.check(Files.cancel(),"desktop back can cancel")
T.check(not Files.pending(),"cancelled drop job is gone")
T.check(not Files.filedropped(dropped("later.json","good")),"late JSON cannot apply to cancelled session")
reset("Linux");Files.import(options,hooks());file=dropped("large.json","good",{size=33});Files.filedropped(file)
T.eq(#applied,0,"oversize desktop drop never applies")
T.eq(file.closed,1,"oversize desktop file closes")
reset("Linux");Files.import(options,hooks());file=dropped("error.json","good",{readThrows=true});Files.filedropped(file)
T.eq(#applied,0,"desktop read exception never applies")
T.eq(file.closed,1,"desktop read exception still closes opened file")
reset("Linux");T.check(Files.export(options,hooks()),"desktop export writes directly")
T.eq(fs["exports/kanto-player-settings.json"],"export fixture","desktop export contains encoded options")
T.check(not Files.pending(),"desktop export needs no pending job")

love=realLove;package.loaded["src.import.SettingsTransfer"]=realCodec
package.loaded["src.import.SettingsFiles"]=nil
T.finish("settings native file lifecycle")
