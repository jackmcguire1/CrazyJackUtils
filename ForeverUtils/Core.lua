local ADDON, ns = ...

ns.DEFAULTS = {
  enabled = true,
  minimapHide = false,
  minimapAngle = 225,
  debug = false,
  modules = {}, -- [module.key] = that module's settings, including `enabled`
}

-- Slash command words a module key can't shadow.
local RESERVED = { on = true, off = true, status = true, debug = true }

ns.modules = {} -- in registration order
local byKey = {}
local db

local frame = CreateFrame("Frame")

local function Print(fmt, ...)
  print("|cff33ccffForeverUtils|r: " .. fmt:format(...))
end
ns.Print = Print

function ns.Debug(fmt, ...)
  if db and db.debug then Print("|cff888888" .. fmt .. "|r", ...) end
end

-- Copies missing settings from `defaults` into `target`, descending into tables.
local function FillDefaults(target, defaults)
  for k, v in pairs(defaults) do
    if type(v) == "table" then
      if type(target[k]) ~= "table" then target[k] = {} end
      FillDefaults(target[k], v)
    elseif target[k] == nil then
      target[k] = v
    end
  end
end

---------------------------------------------------------------------------
-- Modules
---------------------------------------------------------------------------

-- Registers a feature. Call it while the module's file loads. Fields:
--   key          lowercase id: the saved-variable key and the word after /fu
--   name         shown in the options and in chat
--   description  optional note under the module's checkbox
--   defaults     optional settings; `enabled = false` makes the module opt-in
--   events       optional { EVENT_NAME = function(module, ...) }, called only while enabled
--   OnInit       optional, called once when saved variables are ready (module.db is set)
--   OnEnable     optional, called when the module turns on, including at login
--   OnDisable    optional, called when the module turns off
--   BuildOptions optional function(module, UI, anchor): add controls under the module's
--                checkbox with ns.UI and return the last one
function ns.RegisterModule(module)
  local key = module.key
  assert(type(key) == "string" and key:match("^[a-z][a-z0-9_]*$"), "module key must be lowercase [a-z0-9_]")
  assert(not RESERVED[key], "module key '" .. key .. "' is a slash command")
  assert(not byKey[key], "module '" .. key .. "' is already registered")
  assert(not db, "register module '" .. key .. "' while its file loads, not later")
  module.name = module.name or key
  module.active = false
  byKey[key] = module
  table.insert(ns.modules, module)
  return module
end

-- Turns each module on or off to match the settings.
function ns.Refresh()
  for _, module in ipairs(ns.modules) do
    local want = db.enabled and module.db.enabled
    if want ~= module.active then
      module.active = want
      ns.Debug("%s %s", module.key, want and "enabled" or "disabled")
      local callback = want and module.OnEnable or module.OnDisable
      if callback then callback(module) end
    end
  end
end

function ns.SetEnabled(enabled)
  db.enabled = enabled
  ns.Refresh()
  Print(enabled and "on" or "off")
end

local function InitModule(module)
  if type(db.modules[module.key]) ~= "table" then db.modules[module.key] = {} end
  module.db = db.modules[module.key]
  FillDefaults(module.db, module.defaults or {})
  if module.db.enabled == nil then module.db.enabled = true end
  for event in pairs(module.events or {}) do frame:RegisterEvent(event) end
  if module.OnInit then module:OnInit() end
end

---------------------------------------------------------------------------
-- Setup
---------------------------------------------------------------------------

frame:RegisterEvent("ADDON_LOADED")

frame:SetScript("OnEvent", function(_, event, ...)
  if not db then
    if event ~= "ADDON_LOADED" or ... ~= ADDON then return end
    ForeverUtilsDB = ForeverUtilsDB or {}
    db = ForeverUtilsDB
    FillDefaults(db, ns.DEFAULTS)
    ns.db = db
    for _, module in ipairs(ns.modules) do InitModule(module) end
    ns.InitOptions()
    ns.InitMinimap()
    ns.Refresh()
    return
  end
  for _, module in ipairs(ns.modules) do
    local handler = module.active and module.events and module.events[event]
    if handler then handler(module, ...) end
  end
end)

SLASH_FOREVERUTILS1 = "/foreverutils"
SLASH_FOREVERUTILS2 = "/fu"

SlashCmdList.FOREVERUTILS = function(input)
  local cmd, arg = (input or ""):lower():match("^%s*(%S*)%s*(.-)%s*$")
  local module = byKey[cmd]
  if cmd == "" and ns.OpenOptions then
    ns.OpenOptions()
  elseif cmd == "on" or cmd == "off" then
    ns.SetEnabled(cmd == "on")
  elseif cmd == "debug" then
    db.debug = not db.debug
    Print("debug %s", db.debug and "on" or "off")
  elseif cmd == "status" then
    local states = {}
    for _, m in ipairs(ns.modules) do
      table.insert(states, ("%s %s"):format(m.key, m.db.enabled and "on" or "off"))
    end
    Print("%s, %s", db.enabled and "enabled" or "disabled",
      #states > 0 and table.concat(states, ", ") or "no modules installed")
  elseif module and (arg == "" or arg == "on" or arg == "off") then
    -- "/fu <module>" toggles it, "/fu <module> on|off" sets it.
    if arg == "" then module.db.enabled = not module.db.enabled else module.db.enabled = arg == "on" end
    ns.Refresh()
    Print("%s %s", module.name, module.db.enabled and "on" or "off")
  else
    Print("/fu - options | on | off | status | debug | <module> [on|off]")
  end
end
