-- SPDX-License-Identifier: GPL-3.0-only
-- User-requested settings files. The codec never executes configuration code.
-- Android reuses the engine's generic document picker and export staging path.
local Files = {}
local PICK = "picked_settings.json"
local EXPORT = "kanto-player-settings.json"
local EXPORT_RESULT = "export_result.flag"
local job
local function ownError(value)
  return value == PICK or value == "cancelled:" .. PICK
end
local function ownComplete(value)
  return value == PICK or (type(value) == "string" and value:match("^v1\n([^\n]+)\n") == PICK)
end

local function notify(hooks, message, ok)
  if hooks and hooks.notify then hooks.notify(message, ok == true) end
end
local function complete(hooks, status, detail)
  if hooks and hooks.complete then pcall(hooks.complete, status, detail) end
end
local function done(message, ok, status)
  local previous = job
  job = nil
  if previous then
    notify(previous.hooks, message, ok)
    if status then complete(previous.hooks, status, message) end
  end
end
local function exportResult(value, name)
  if type(value) ~= "string" then return nil end
  local target, status = value:match("^v1\n([^\n]+)\n([^\n]+)\n?$")
  if target == name and (status == "ok" or status == "cancelled" or status == "error") then
    return status
  end
end
local function apply(data, options, hooks)
  local candidate, err = require("src.import.SettingsTransfer").import(data, options)
  if not candidate then
    notify(hooks, "せっていを よめませんでした。\n" .. tostring(err), false)
    return false
  end
  local ok, result, failure = pcall(hooks.apply, candidate)
  if not ok or not result then
    notify(hooks, "せっていを ほぞんできません。\n" .. tostring(failure or result or ""), false)
    return false
  end
  notify(hooks, "せっていを よみこみました。", true)
  return true
end

function Files.pending() return job ~= nil end

function Files.import(options, hooks)
  if job then return false end
  hooks = hooks or {}
  if type(hooks.apply) ~= "function" then return false end
  if love.system.getOS() == "Android" and love.system.pickFile then
    -- Only delete our own stale staging artifact. A completed ROM/MOD picker
    -- has independent names and is never consumed as a settings file.
    love.filesystem.remove(PICK)
    if ownError(love.filesystem.read("pick_error.flag")) then love.filesystem.remove("pick_error.flag") end
    if ownComplete(love.filesystem.read("pick_complete.flag")) then love.filesystem.remove("pick_complete.flag") end
    job = { kind = "import", options = options, hooks = hooks }
    local ok, opened = pcall(love.system.pickFile, "required_import", PICK)
    if ok and opened then return true end
    done("ファイルを ひらけませんでした。", false)
    return false
  end
  -- Desktop: a dropped JSON is routed here even without a system dialog.
  job = { kind = "drop", options = options, hooks = hooks }
  notify(hooks, "せっていの JSONファイルを\nこの がめんに ドロップしてね。\nもどるで やめられます。", true)
  return true
end

function Files.export(options, hooks)
  hooks = hooks or {}
  local data, err = require("src.import.SettingsTransfer").export(options)
  if not data then notify(hooks, "せっていを かきだせませんでした。\n" .. tostring(err), false); return false end
  return Files.exportData(data, EXPORT, {
    notify=hooks.notify, complete=hooks.complete, label="せってい",
  })
end

-- Shared document export also serves the bundled MOD's diagnostic log. Keep
-- one staging owner and one native result consumer while gameplay is paused.
function Files.exportData(data, filename, hooks)
  hooks = hooks or {}
  local function failed(message)
    notify(hooks, message, false);complete(hooks, "error", message);return false
  end
  if job then return failed("ほかの ファイルを\nよみかきしています。") end
  if type(data) ~= "string" or type(filename) ~= "string" or filename == ""
      or #filename > 255 or filename:find("[/\\%z\1-\31]") then
    return failed("ファイルを かきだせません。")
  end
  local label = hooks.label or "ファイル"
  if love.system.getOS() == "Android" then
    if love.filesystem.getInfo("pending_export.sav", "file")
        or love.filesystem.getInfo("export_done.flag", "file") then
      return failed("ほかの かきだしが のこっています。\nそちらを おえてから\nもういちど おためしください。")
    end
    if exportResult(love.filesystem.read(EXPORT_RESULT), filename) then
      love.filesystem.remove(EXPORT_RESULT)
    end
    local wrote = love.filesystem.write("pending_export.sav", data)
    if not wrote then
      love.filesystem.remove("pending_export.sav")
      return failed("ファイルを かけませんでした。")
    end
    job = { kind = "export", hooks = hooks, filename = filename, label = label }
    local ok, opened = pcall(function()
      return love.system.createFile and love.system.createFile(filename)
    end)
    if ok and opened then return true end
    love.filesystem.remove("pending_export.sav")
    done("ほぞんさきを ひらけませんでした。", false, "error")
    return false
  end
  love.filesystem.createDirectory("exports")
  local relative = "exports/" .. filename
  local wrote = love.filesystem.write(relative, data)
  if not wrote then return failed("ファイルを かけませんでした。") end
  notify(hooks, label .. "を かきだしました。\n" .. love.filesystem.getSaveDirectory() .. "/" .. relative, true)
  complete(hooks, "ok", relative)
  return true
end

function Files.cancel()
  if not job then return false end
  if job.kind == "drop" then job = nil; return true end
  return false
end

function Files.filedropped(file)
  if not (job and job.kind == "drop") then return false end
  local name = file and file.getFilename and file:getFilename() or ""
  if not name:lower():match("%.json$") then return false end
  local current = job
  job = nil
  local opened = false
  local ok, data = pcall(function()
    assert(file:open("r"))
    opened = true
    local size = file:getSize()
    if size > require("src.import.SettingsTransfer").MAX_BYTES then error("File too large") end
    local bytes = file:read(size)
    return bytes
  end)
  if opened then pcall(file.close, file) end
  if ok then apply(data, current.options, current.hooks)
  else notify(current.hooks, "ファイルを よめませんでした。", false) end
  return true
end

function Files.focus(focused)
  if not job or job.kind == "drop" then return end
  if not focused then job.lostFocus = true
  elseif job.lostFocus then job.returned = 0 end
end

function Files.update(dt)
  if not job or job.kind == "drop" then return false end
  if job.kind == "export" then
    local result = exportResult(love.filesystem.read(EXPORT_RESULT), job.filename)
    if result then
      love.filesystem.remove(EXPORT_RESULT)
      -- Native writes this legacy success marker before the explicit result.
      if result == "ok" then love.filesystem.remove("export_done.flag") end
      love.filesystem.remove("pending_export.sav")
      if result == "ok" then done(job.label .. "を かきだしました。", true, "ok")
      elseif result == "cancelled" then done("かきだしを ちゅうししました。", false, "cancelled")
      else done("ファイルを かけませんでした。\nほぞんさきを かえて\nもういちど おためしください。", false, "error") end
      return false
    end
    -- Focus/visibility can change while SAF is still open. Only Android's
    -- onActivityResult knows whether it was saved, cancelled or failed.
    return true
  else
    local failure = love.filesystem.read("pick_error.flag")
    if ownError(failure) then
      love.filesystem.remove("pick_error.flag")
      done("ファイルを よめませんでした。", false)
      return false
    end
    local info = love.filesystem.getInfo(PICK, "file")
    -- Basename imports have no native completion marker. GameActivity writes
    -- them on its UI thread; focus returns only after that copy has completed.
    if info and job.returned ~= nil then
      local current = job
      local limit = require("src.import.SettingsTransfer").MAX_BYTES
      local data = (info.size or 0) <= limit and love.filesystem.read(PICK) or nil
      job = nil
      love.filesystem.remove(PICK)
      local marker = love.filesystem.read("pick_complete.flag")
      if ownComplete(marker) then love.filesystem.remove("pick_complete.flag") end
      if data then apply(data, current.options, current.hooks)
      else notify(current.hooks, "ファイルを よめませんでした。", false) end
      return false
    end
  end
  -- The native activity signals success/error before focus returns. It does
  -- not signal cancellation. A short grace period also tolerates event order.
  if job.returned then
    job.returned = job.returned + (dt or 0)
    if job.returned > 0.5 then
      if job.kind == "export" then love.filesystem.remove("pending_export.sav") end
      done("ファイルの よみかきを\nちゅうししました。", false)
      return false
    end
  end
  return true
end

return Files
