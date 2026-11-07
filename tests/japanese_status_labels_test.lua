-- Display localization is independent of saved status ids and MOD records.
package.path="./?.lua;./?/init.lua;"..package.path
love=require("tests.love_stub")
local T=require("tests.harness")
local Strings=require("src.core.Strings")
local Status=require("src.battle.Status")
local labels={PSN="どく",PAR="まひ",BRN="やけど",FRZ="こおり",SLP="ねむり",FNT="ひんし"}
Strings.load({constants={language="ja"}})
for id,label in pairs(labels)do
  T.eq(Status.hudLabelFor(nil,id),label,id.." uses compact Japanese display label")
  if Status.RECORDS[id]then
    T.eq(Status.RECORDS[id].id,id,"status id remains serializable as "..id)
    T.eq(Status.RECORDS[id].label,id,"registry source label remains unchanged")
  end
end
T.eq(Status.hudLabelFor(nil,nil),nil,"healthy status remains absent")
T.eq(Strings("OK","status"),"ふつう","summary healthy status is Japanese")
T.eq(Strings("OK"),"OK","unrelated OK buttons keep their existing wording")
T.eq(Status.hudLabelFor({PSN={label="毒のしるし"}},"PSN"),"毒のしるし","MOD label override remains authoritative")
T.eq(Status.hudLabelFor({PSN={label="PSN",hudLabel="TOX"}},"PSN"),"TOX","MOD HUD override is not overwritten from its id")
T.eq(Status.hudLabelFor({CUSTOM={label="カスタム"}},"CUSTOM"),"カスタム","custom status labels remain available")

package.loaded["src.core.Sound"]={play=function()end}
package.loaded["src.world.PikachuFollower"]={modifyHappiness=function()end}
local Items=require("src.inventory.ItemEffects")
for item,id in pairs({ANTIDOTE="PSN",PARLYZ_HEAL="PAR",BURN_HEAL="BRN",ICE_HEAL="FRZ",AWAKENING="SLP"})do
  local mon={nickname="ピカチュウ",species="PIKACHU",hp=20,stats={hp=30},status=id}
  local data={constants={language="ja"},items={},pokemon={PIKACHU={name="ピカチュウ"}}}
  local result,messages=Items.use(data,{party={mon},player={name="レッド"}},item,mon)
  T.eq(result,"consumed",item.." still recognizes original status enum")
  T.eq(mon.status,nil,item.." still cures the same status")
  T.eq(messages[1],"ピカチュウの\nじょうたいが もとに\nもどった！",item.." fallback healing message is Japanese")
end
local mon={name="ピカチュウ",mon={status="SLP"},sleepTurns=1}
local _,messages=Status.RECORDS.SLP.beforeMove(mon,nil,{data={}})
T.eq(messages[1],"ピカチュウは\nめを さました！","waking status fallback is Japanese")
T.eq(mon.mon.status,nil,"waking keeps original status-clear behavior")

Strings.load({})
for id in pairs(labels)do T.eq(Status.hudLabelFor(nil,id),id,"English status "..id.." is unchanged")end
T.eq(Strings("OK","status"),"OK","English healthy status is unchanged")
Strings.load({strings={PSN="VEN",["status|PAR"]="PRZ"}})
T.eq(Status.hudLabelFor(nil,"PSN"),"VEN","other-language status catalog is honored")
T.eq(Status.hudLabelFor(nil,"PAR"),"PRZ","other-language status context is honored")
Strings.load({})
T.finish("Japanese status presentation")
