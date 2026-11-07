-- Actual bundled MOD + shared controller, with native document boundaries
-- mocked. No retail save or ROM is needed to exercise this export.
package.path="./?.lua;./?/init.lua;"..package.path
local T=require("tests.harness")
local fs,picks,events,Files,Export,writeFail,openFail
local NAME="DramalessShape-log.txt"
local BYTES="diagnostic fixture\nかな\n\0binary-safe log\n"
local function reset()
  fs,picks,events={},{},{}
  writeFail,openFail=false,false
  love={system={getOS=function()return"Android"end,
    createFile=function(name)picks[#picks+1]=name;return not openFail end},filesystem={}}
  function love.filesystem.getInfo(path)if fs[path]then return{size=#fs[path],type="file"}end end
  function love.filesystem.read(path)return fs[path]end
  function love.filesystem.remove(path)fs[path]=nil;return true end
  function love.filesystem.write(path,bytes)
    if writeFail then fs[path]="partial";return false,"storage unavailable"end
    fs[path]=bytes;return true
  end
  function love.filesystem.getSaveDirectory()return"/private/app/save/gen1recomp-japanese"end
  package.loaded["src.import.SettingsFiles"]=nil
  Files=require("src.import.SettingsFiles")
  Export=assert(loadfile("vendor/jp-mods/DRAMALESS_SHAPE/lib/DramalessLogExport.lua"))({log={
    contents=function()return BYTES end,
    event=function(_,kind,name,detail)events[#events+1]={kind,name,detail}end,
  }})
end
local function result(status,name)
  fs["export_result.flag"]="v1\n"..(name or NAME).."\n"..status.."\n"
  if status=="ok"then fs["export_done.flag"]="ok"end
  return Files.update(0)
end
local function state()return Export.row().value()end

reset()
T.check(Export.export(),"Android diagnostic row opens SAF instead of immediate cancellation")
T.eq(picks[1],NAME,"SAF suggests diagnostic .txt filename")
T.eq(fs["pending_export.sav"],BYTES,"staging preserves complete UTF-8 and binary log bytes")
T.eq(state(),"WAITING","row waits for actual native result")
T.check(not Export.export(),"second tap does not launch overlapping picker")
T.eq(#picks,1,"one native picker per export")
Files.focus(false);Files.focus(true)
T.check(Files.update(60),"transient focus/visibility return cannot cancel export")
T.eq(state(),"WAITING","long document browsing remains pending")
T.eq(fs["pending_export.sav"],BYTES,"focus events cannot delete in-flight source")
T.check(result("cancelled","different-file.txt"),"another document's result is not consumed")
T.eq(fs["export_result.flag"],"v1\ndifferent-file.txt\ncancelled\n","foreign result is preserved")
T.check(not result("ok"),"matching native success finishes pending operation")
T.eq(state(),"SAVED","success reaches diagnostic row")
T.eq(fs["pending_export.sav"],nil,"successful staging is cleaned")
T.eq(fs["export_done.flag"],nil,"legacy success marker is consumed by owner")
T.eq(fs["export_result.flag"],nil,"matching explicit result is consumed")
T.eq(events[1][2],"exported","successful export is logged once")
Files.update(10);T.eq(#events,1,"later updates cannot repeat success callback")

reset();Export.export();result("cancelled")
T.eq(state(),"CANCELLED","only explicit native cancellation reports cancelled")
T.eq(fs["pending_export.sav"],nil,"cancelled source staging is cleaned")
T.check(not Files.pending(),"cancel releases shared document controller")
T.eq(#events,0,"cancel is never logged as a successful write")
T.check(Export.export(),"cancel permits a fresh retry")
result("error")
T.eq(state(),"FAILED","provider write error is distinct from cancellation")
T.eq(events[1][2],"export-failed","provider failure is recorded")
T.eq(fs["pending_export.sav"],nil,"failed export staging is cleaned")
T.check(not Files.pending(),"provider failure releases controller")

reset();openFail=true
T.check(not Export.export(),"unavailable picker fails immediately")
T.eq(state(),"FAILED","picker-open failure is not cancellation")
T.eq(fs["pending_export.sav"],nil,"picker-open failure removes own staging")
reset();writeFail=true
T.check(not Export.export(),"staging write failure stops export")
T.eq(#picks,0,"failed staging never opens document picker")
T.eq(state(),"FAILED","staging failure is visible")
T.eq(fs["pending_export.sav"],nil,"partial failed staging is removed")
reset();fs["pending_export.sav"]="existing save bytes"
T.check(not Export.export(),"existing cartridge/settings export is protected")
T.eq(fs["pending_export.sav"],"existing save bytes","foreign pending bytes remain exact")
T.eq(#picks,0,"protected export cannot open second picker")
reset();fs["export_result.flag"]="v1\n"..NAME.."\nok\n"
Export.export();Files.update(0)
T.eq(state(),"WAITING","stale same-name result cannot complete fresh request")
T.eq(fs["export_result.flag"],nil,"own stale result is cleared")
reset()
T.eq(Export.row().step(),false,"menu command does not report an option mutation")
T.eq(#picks,1,"command row still opens SAF when change result is false")
T.eq(state(),"WAITING","command status remains live for paused menu rendering")
T.finish("Android diagnostic document export")
