-- Actual LÖVE threads and production ExtractThread/constructor/metadata/cache
-- IO. Only the extraction body's large ROM-dependent traversal is replaced.
local S = require("tests.harness").suite("Japanese revision actual worker")
local Manifest = require("src.import.RomManifest")
local Contract = require("src.import.CacheContract")
local Json = require("src.link.Json")
local rows = {
  {sha1="0623ad12f48c259447980d68bd85ddbf8204b2cd", address=32704, bound=64},
  {sha1="ef74c79cded14204ac79e77f4964d9cb25003120", address=32666, bound=102},
}
local workerSource = [[
  require("love.filesystem")
  require("love.thread")
  local Extractor = require("src.import.RomExtractor")
  Extractor.run = function(self)
    local symbol = self:symbol("_GettingPumpedText")
    local output = require("src.link.Json").encode({sha1=self.manifest.romSha1,
      address=symbol.address, bound=self.manifest.text.lengths[symbol.name],
      text=self:decodeTextCommands(symbol,{})})
    assert(require("src.import.CacheFs").write("data/generated/revision-qa.json",output))
    self.progress(1,1,"fixture",1,1)
  end
  assert(love.filesystem.load("src/import/ExtractThread.lua"))(...)
]]
local function run()
  local timings = {}
  for index, row in ipairs(rows) do
    local time = love.timer.getTime()
    for _ = 1, 10 do Manifest.decode("red_jp",row.sha1) end
    timings[tostring(index-1)] = (love.timer.getTime()-time)*100
    local offset = 9*0x4000+row.address%0x4000
    local synthetic = string.rep("\255",offset)..string.char(0,0x80,0x57)..string.rep("\255",524288-offset-3)
    local prefix = "fixture/"..index.."/"
    local progress, result = "jp13-progress", "jp13-result"
    love.thread.getChannel(progress):clear(); love.thread.getChannel(result):clear()
    local thread = love.thread.newThread(love.filesystem.newFileData(workerSource,"revision-worker.lua"))
    thread:start("red_jp",prefix,synthetic,progress,result,row.sha1)
    thread:wait()
    S.eq(thread:getError(),nil,"actual LÖVE worker exited normally")
    local complete = love.thread.getChannel(result):pop()
    S.check(complete and complete.ok,"actual extraction entry succeeded: "..tostring(complete and complete.error))
    local output = assert(Json.decode(assert(love.filesystem.read(prefix.."data/generated/revision-qa.json"))))
    S.eq(output.sha1,row.sha1,"worker selected exact metadata hash")
    S.eq(output.address,row.address,"worker selected relocated text")
    S.eq(output.bound,row.bound,"worker selected bounded span")
    S.eq(output.text,"ア{DONE}","worker parser stops before invalid padding")
    S.check(love.thread.getChannel(progress):pop() ~= nil,"progress crosses real thread channel")
    S.check(Contract.markerMatches("red_jp",Contract.markerFor("red_jp",row.sha1)),"both worker revisions reopen same cache identity")
  end
  local out = assert(os.getenv("JP_REVISION_OUT"))
  local file = assert(io.open(out.."/actual-worker-results.json","wb"))
  file:write(Json.encode({checks=16, failures=0, metadataDecodeMeanMs=timings,
    scope="Authored synthetic bytes only; actual LÖVE worker and extractor text parser; no full cartridge extraction."})); file:close()
  S.finish()
end
function love.load()
  local ok, err = xpcall(run, debug.traceback)
  if not ok then print(err) end
  love.event.quit(ok and 0 or 1)
end
