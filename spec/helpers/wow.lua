-- A fake WoW client, just big enough to run Core.lua and modules. Each call to
-- wow.load() gives the addon a fresh global environment, so no state leaks between tests.

local M = {}

local function NewFrame()
  local frame = { events = {}, scripts = {} }
  function frame:RegisterEvent(event) self.events[event] = true end
  function frame:SetScript(name, fn) self.scripts[name] = fn end
  return frame
end

-- opts.db:      saved variables to start with.
-- opts.modules: module tables to register, as a module's file would while loading.
-- opts.files:   module files to load after Core.lua, e.g. { "CrazyJackUtils/Modules/AutoSell.lua" }.
-- opts.env:     extra globals (WoW API stand-ins) for the module under test.
function M.load(opts)
  opts = opts or {}
  local w = {
    frames = {},
    printed = {},
    optionsOpened = 0,
  }

  local env = setmetatable({}, { __index = _G })
  env._G = env
  env.print = function(msg) table.insert(w.printed, msg) end
  env.CreateFrame = function()
    local frame = NewFrame()
    table.insert(w.frames, frame)
    return frame
  end
  env.SlashCmdList = {}
  env.CrazyJackUtilsDB = opts.db
  for name, value in pairs(opts.env or {}) do env[name] = value end

  local ns = {
    InitOptions = function() end,
    InitMinimap = function() end,
    OpenOptions = function() w.optionsOpened = w.optionsOpened + 1 end,
  }
  w.env, w.ns = env, ns

  local files = { "CrazyJackUtils/Core.lua" }
  for _, file in ipairs(opts.files or {}) do table.insert(files, file) end
  for _, file in ipairs(files) do
    local chunk = assert(loadfile(file))
    setfenv(chunk, env)
    chunk("CrazyJackUtils", ns)
  end
  for _, module in ipairs(opts.modules or {}) do ns.RegisterModule(module) end

  function w:Fire(event, ...)
    for _, frame in ipairs(self.frames) do
      if frame.events[event] and frame.scripts.OnEvent then frame.scripts.OnEvent(frame, event, ...) end
    end
  end

  function w:Slash(input) env.SlashCmdList.CRAZYJACKUTILS(input) end

  w:Fire("ADDON_LOADED", "CrazyJackUtils")
  w.db = env.CrazyJackUtilsDB
  return w
end

-- A module that records its callbacks in module.calls, for testing Core.
function M.module(key, fields)
  local module = { key = key, calls = {} }
  local function record(name)
    return function(self, ...) table.insert(self.calls, { name, ... }) end
  end
  module.OnInit, module.OnEnable, module.OnDisable = record("OnInit"), record("OnEnable"), record("OnDisable")
  module.events = { SOME_EVENT = record("SOME_EVENT") }
  for k, v in pairs(fields or {}) do module[k] = v end
  return module
end

return M
