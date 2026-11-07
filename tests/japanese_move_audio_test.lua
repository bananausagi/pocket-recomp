-- Synthetic ROM banks only. Exercise extraction -> cache repair -> the real
-- ChipSynth renderer -> Sound.playMove. No retail ROM programs or PCM here.
package.path="./?.lua;./?/init.lua;"..package.path
love=require("tests.love_stub")
local T=require("tests.harness").suite("Japanese move audio")
local Json=require("src.link.Json")
local Extractor=require("src.import.RomExtractor")
local Chip=require("src.core.ChipSynth")
local ChipAudio=require("src.core.ChipAudio")
local Sound=require("src.core.Sound")
local Repair=require("src.core.JapaneseAudio")
local Version=require("src.core.GameVersion")
local f=assert(io.open("tools/rom_manifest_red_jp.json","rb"))
local manifest=assert(Json.decode(f:read("*a")));f:close()
local function clone(x)
  if type(x)~="table" then return x end
  local y={};for k,v in pairs(x)do y[k]=clone(v)end;return y
end
local count=0
for id,name in pairs(manifest.sfxKeys)do
  local def=manifest.audio.sfxHeaders[name]
  T.check(def~=nil,"sound ID "..id.." resolves to an imported header")
  T.eq((def.address-manifest.audio.sfxHeaderBases["2"].address)/3,tonumber(id),
    "sound ID "..id.." uses its engine's table base")
  count=count+1
end
T.eq(count,56,"all 56 named battle-bank SFX mapped")
T.eq(manifest.audio.sfxHeaderBases["2"].address,0x6c92,"JP Red battle SFX table address")
T.eq(manifest.sfxKeys["160"],"Pound","known Pound ID $a0")
T.eq(manifest.sfxKeys["166"],"Damage","known Scratch/Damage ID $a6")
T.eq(manifest.sfxKeys["176"],"Super_Effective","known Tackle effect ID $b0")

local banks={};for i=0,31 do banks[i]=string.rep("\0",0x4000)end
local function put(bank,address,bytes)
  local at=address%0x4000
  banks[bank]=banks[bank]:sub(1,at)..bytes..banks[bank]:sub(at+#bytes+1)
end
local function bytes(...)return string.char(...)end
local nextBody={[2]=0x7600,[8]=0x7600,[31]=0x7600}
local function program(header,channels,music)
  local descriptors={}
  for i,ch in ipairs(channels)do
    local address=nextBody[header.bank];nextBody[header.bank]=address+16
    descriptors[#descriptors+1]=bytes((i==1 and (#channels-1)*64 or 0)+ch-1,address%256,math.floor(address/256))
    -- Invented short test tones, deliberately unrelated to game effects.
    local code=music and bytes(0xd1,0xf1,0xe4,0x17,0xff)
      or ch==8 and bytes(0x27,0xf1,0x23,0xff)
      or bytes(0xec,2,0x27,0xf1,0,6,0xff)
    put(header.bank,address,code)
  end
  put(header.bank,header.address,table.concat(descriptors))
end
for _,name in ipairs({"Pound","Damage","Super_Effective","Vine_Whip","Battle_1B"})do
  program(manifest.audio.sfxHeaders[name],{8})
end
program(manifest.audio.sfxHeaders.Trainer_Appeared,{5})
program(manifest.audio.sfxHeaders.Battle_31,{5,6})
program(manifest.audio.sfxHeaders.Press_AB,{5})
program(manifest.audio.cryHeaders["0"],{5})
program(manifest.audio.musicHeaders.Music_PalletTown,{1},true)

local cases={{"POUND",160,0,128,"Pound"},{"SCRATCH",166,0,128,"Damage"},
  {"TACKLE",176,16,160,"Super_Effective"},{"VINE_WHIP",171,1,128,"Vine_Whip"},
  {"PAY_DAY",233,0,255,"Trainer_Appeared"},{"LEER",219,255,64,"Battle_31"}}
local m=clone(manifest);m.constants.moveOrder={};m.constants.speciesOrder={"FIXMON"}
local moveTable,nameTable,soundTable=m.symbols.Moves,m.symbols.MoveNames,m.symbols.MoveSoundTable
for i,c in ipairs(cases)do
  m.constants.moveOrder[i]=c[1]
  put(moveTable[1],moveTable[2]+(i-1)*6,bytes(i,0,40,0,255,35))
  put(nameTable[1],nameTable[2]+(i-1)*2,bytes(0x80,0x50))
  put(soundTable[1],soundTable[2]+(i-1)*3,bytes(c[2],c[3],c[4]))
end
put(m.audio.cryData.bank,m.audio.cryData.address,bytes(0,0,128))
local rom={};for i=0,31 do rom[#rom+1]=banks[i]end;rom=table.concat(rom)
local function extract(spec)
  local ex=Extractor.new(rom,spec)
  ex.animationFlags=function(_,n)local flags={};for i=1,n do flags[i]={false,false}end;return flags end
  ex.write=function()end
  return {constants={language="ja"},moves=ex:extractMoves(),audio=ex:extractAudio()}
end
local data=extract(m)
T.eq(#assert(love.filesystem.read(data.audio.programFile)),3*0x4000,"extracts all three complete audio banks")
for _,c in ipairs(cases)do
  T.eq(data.moves[c[1]].anim.sound,c[5],c[1].." extraction resolves sound")
  T.eq(data.moves[c[1]].anim.pitch,c[3],c[1].." pitch byte retained")
  T.eq(data.moves[c[1]].anim.tempo,c[4],c[1].." tempo byte retained")
end

local sources={}
local Source={};Source.__index=Source
function Source:play()self.playing=true end
function Source:stop()self.playing=false end
function Source:pause()self.playing=false end
function Source:isPlaying()return self.playing end
function Source:setLooping(v)self.looping=v end
function Source:setVolume(v)self.volume=v end
function Source:setPitch(v)self.pitch=v end
function Source:getPitch()return self.pitch or 1 end
function Source:setFilter()end
function Source:getDuration()return self.pcm:getDuration()end
function Source:tell()return 0 end
love.audio={newSource=function(pcm)
  local src=setmetatable({pcm=pcm},Source);sources[#sources+1]=src;return src
end}
local function peak(pcm)
  local n=0;for i=0,pcm:getSampleCount()-1 do n=math.max(n,math.abs(pcm:getSample(i,1)))end;return n
end
local function reset()Sound.invalidate();Chip.invalidateBanks();sources={}end
Version.set("red_jp")
local oldManifest=clone(m);oldManifest.sfxKeys={};oldManifest.audio.sfxHeaderBases=nil
oldManifest.audio.sfxHeaders.Trainer_Appeared=nil
local old=extract(oldManifest)
reset();Sound.playMove(old,old.moves.POUND.anim)
T.eq(old.moves.POUND.anim.sound,"SFX_A0","reproduces pre-fix cache's unresolved name")
T.eq(#sources,0,"pre-fix unresolved effect produces no playback source")
local menuBefore=Sound.play(old,"Press_AB")
T.check(menuBefore and peak(menuBefore.pcm)>0.01,"menu beep already works despite missing move SFX")
local cryBefore=Sound.playCry(old,"FIXMON")
T.check(cryBefore and peak(cryBefore.pcm)>0.01,"species cry already works before repair")
local musicBefore=Chip.soundData(Chip.newEngine(old,old.audio.songs.Music_PalletTown),1000,2)
T.check(peak(musicBefore)>0.01,"music bank program already renders before repair")
local sourceBefore=old.audio.programFile
local bankBefore=love.filesystem.read(sourceBefore)
local menuDef,cryDef,songDef=old.audio.sfx.Press_AB,old.audio.cries.FIXMON,old.audio.songs.Music_PalletTown
setmetatable(old,{__index=require("src.core.Data")})
old:seedDefaults("red_jp")
T.eq(old.audio.programFile,sourceBefore,"repair keeps program cache path")
T.eq(love.filesystem.read(sourceBefore),bankBefore,"repair never rewrites audio bank bytes")
T.eq(old.audio.sfx.Press_AB,menuDef,"menu definition preserved")
T.eq(old.audio.cries.FIXMON,cryDef,"cry definition preserved")
T.eq(old.audio.songs.Music_PalletTown,songDef,"music definition preserved")
T.eq(old.audio.sfx.Trainer_Appeared,old.audio.sfx.Silph_Scope,"legacy Silph Scope name gains equivalent engine alias")
for _,c in ipairs(cases)do
  T.eq(old.moves[c[1]].anim.sound,c[5],c[1].." old cache repaired without reimport")
  reset();Sound.playMove(old,old.moves[c[1]].anim)
  T.eq(#sources,1,c[1].." starts one playback source after repair")
  T.check(sources[1] and sources[1].playing,c[1].." playback started")
  T.check(sources[1] and peak(sources[1].pcm)>0.01,c[1].." synthesized PCM is non-silent")
  T.eq(sources[1] and sources[1].pcm:getChannelCount(),2,c[1].." source remains stereo")
end
reset()
local menuAfter=Sound.play(old,"Press_AB")
local cryAfter=Sound.playCry(old,"FIXMON")
local musicAfter=Chip.soundData(Chip.newEngine(old,old.audio.songs.Music_PalletTown),1000,2)
local function pcmEqual(a,b)
  if a:getSampleCount()~=b:getSampleCount()then return false end
  for i=0,a:getSampleCount()-1 do if a:getSample(i,1)~=b:getSample(i,1)then return false end end
  return true
end
T.check(pcmEqual(menuBefore.pcm,menuAfter.pcm),"menu PCM identical before/after repair")
T.check(pcmEqual(cryBefore.pcm,cryAfter.pcm),"cry PCM identical before/after repair")
T.check(pcmEqual(musicBefore,musicAfter),"music PCM identical before/after repair")

-- OR of concurrently active CHAN5 and CHAN8 IDs can leave the battle-SFX
-- range temporarily; the modifier delay must use relocated Japanese IDs.
reset()
Sound.playMove(old,{sound="Battle_1B",pitch=0,tempo=128})
local original,plain=ChipAudio.newSfx,nil
ChipAudio.newSfx=function(d,name,pitch,tempo,def,frames)
  plain=frames;return original(d,name,pitch,tempo,def,frames)
end
Sound.playMove(old,old.moves.LEER.anim)
ChipAudio.newSfx=original
T.check(plain and plain>0,"relocated table IDs retain the overlapping-channel modifier delay")

local foreign=extract(oldManifest)
foreign.constants.language=nil
Repair.seed(foreign,"red")
T.eq(foreign.moves.POUND.anim.sound,"SFX_A0","overseas cache is not rewritten")
local custom=extract(oldManifest)
custom.audio.sfx.SFX_A0="custom.wav"
custom.moves.POUND.anim.sound="SFX_A0"
custom.moves.SCRATCH.anim.sound="CUSTOM_MOD_EFFECT"
Repair.seed(custom,"red_jp")
T.eq(custom.moves.POUND.anim.sound,"SFX_A0","explicit custom numeric sound definition respected")
T.eq(custom.moves.SCRATCH.anim.sound,"CUSTOM_MOD_EFFECT","named MOD effect respected")
local already=Json.encode(old.moves);Repair.seed(old,"red_jp")
T.eq(Json.encode(old.moves),already,"cache repair is idempotent")
reset();Version.set("red")
T.finish()
