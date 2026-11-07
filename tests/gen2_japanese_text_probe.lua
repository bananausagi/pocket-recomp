package.path = './?.lua;./?/init.lua;' .. package.path
love = require('tests.love_stub')
local Extractor = require('src.import.RomExtractorGen2')
local bytes = { [0] = 0, 5, 6, 7, 8, 9, 0x57 }
local rom = {}
function rom:byte(_, address) return bytes[address] or 0x50 end
function rom:word(_, address) return self:byte(0,address)+256*self:byte(0,address+1) end
local extractor = setmetatable({rom=rom, edition='gold', manifest={language='ja'}}, Extractor)
local actual = extractor:decodeGen2Text(0, 0, {['5']='ガ',['6']='ギ',['7']='グ',['8']='ゲ',['9']='ゴ'})
assert(actual == 'ガギグゲゴ{DONE}', 'Japanese dakuten lost: '..actual)
bytes = { [0] = 6, 0, 6, 0x57 }
assert(extractor:decodeGen2Text(0, 0, {['6']='ギ'}) == 'ギ{DONE}',
  'TX_PROMPT_BUTTON must still consume the command byte outside a string')
extractor.manifest.language = 'en'
bytes = { [0] = 6, 0, 0x80, 0x57 }
assert(extractor:decodeGen2Text(0, 0, {['128']='A'}) == 'A{DONE}',
  'English command handling changed')
print('Japanese dakuten preserved')
extractor.edition='crystal'; extractor.manifest.language='ja'
bytes = { [0]=0, 0x14, 9, 0x50, 8, 0x3e, 0x21 }
assert(extractor:decodeGen2Text(0,0,{['9']='ゴ'})=='{PLAYER}ゴ',
  'Crystal gendered name or text-to-ASM boundary decoded incorrectly')
print('Crystal Japanese name token and ASM boundary preserved')
