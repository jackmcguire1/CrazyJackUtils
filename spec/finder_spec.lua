local wow = require("spec.helpers.wow")

-- Loads the addon with Target Finder and a fake macro list, units and quest log.
local function load(opts)
  opts = opts or {}
  local game = {
    combat = false,
    macros = {},        -- [index] = { name = ..., body = ... }
    macroListFull = false,
    units = {},         -- [unit] = { name = ..., player = bool, controlled = bool }
    quests = {},        -- list of lists of objectives
    now = 1000,
    loggedIn = true,
    timers = {},
    npcs = opts.npcs,   -- [id] = name: the QuestieDB addon's NPCs; nil if it isn't installed
    questDb = opts.questDb or {}, -- [questID] = QuestieDB objectives
    items = opts.items or {},     -- [itemID] = { name = ..., drops = { npc ids } }
    titles = {},        -- [questID] = title, else "Quest <id>"
    -- [npc id] = { flags = ..., title = ..., faction = "A" | "H" | "AH", spawns = { [area] = { { x, y } } } }
    npcInfo = opts.npcInfo or {},
    secret = {}, -- stands in for a value the game withholds; issecretvalue knows it
    player = { n = 0, w = 0, continent = 0 }, -- nil where the game won't say
    facing = nil,
  }
  -- The fake world: each map is 1000 yards square, with x and y running east and south
  -- from its top left corner.
  local MAPS = {
    [1429] = { continent = 0, n = 1000, w = 1000 }, -- you start at its bottom right corner
    [1411] = { continent = 1, n = 1000, w = 1000 },
  }
  local function info(id, field) return game.npcInfo[id] and game.npcInfo[id][field] end
  local env = {
    InCombatLockdown = function() return game.combat end,
    IsLoggedIn = function() return game.loggedIn end,
    time = function() return game.now end,
    GetMacroIndexByName = function(name)
      for i, macro in ipairs(game.macros) do
        if macro.name == name then return i end
      end
      return 0
    end,
    CreateMacro = function(name, _, body)
      assert(not game.combat, "CreateMacro in combat")
      if game.macroListFull then error("macro list full") end
      table.insert(game.macros, { name = name, body = body })
      return #game.macros
    end,
    EditMacro = function(index, _, _, body)
      assert(not game.combat, "EditMacro in combat")
      game.macros[index].body = body
    end,
    issecretvalue = function(value) return value == game.secret end,
    UnitExists = function(unit) return game.units[unit] ~= nil end,
    UnitName = function(unit) return game.units[unit] and game.units[unit].name end,
    UnitIsPlayer = function(unit) return game.units[unit].player or false end,
    UnitPlayerControlled = function(unit) return game.units[unit].controlled or false end,
    C_Timer = { After = function(_, fn) table.insert(game.timers, fn) end },
    NpcDB = game.npcs and {
      GetAllIds = function()
        local ids = {}
        for id in pairs(game.npcs) do table.insert(ids, id) end
        table.sort(ids)
        return ids
      end,
      name = function(id)
        if game.npcs[id] == "error" then error("bad row") end
        return game.npcs[id]
      end,
      npcFlags = function(id) return info(id, "flags") or 0 end,
      subName = function(id) return info(id, "title") end,
      friendlyToFaction = function(id) return info(id, "faction") end,
      spawns = function(id) return info(id, "spawns") end,
    } or nil,
    LibQuestieDB = game.npcs and not opts.noZones and {
      Support = { Get = function() return { private = {
        areaIdToUiMapId = "return { [12] = 1429, [14] = 9999, [17] = 1411 }",
        areaIdToUiMapIdOverride = "return { [14] = 1429 }",
      } } end },
    } or nil,
    C_Map = { GetWorldPosFromMapPos = function(map, at)
      local corner = assert(MAPS[map], "unknown map")
      return corner.continent, { x = corner.n - at.y * 1000, y = corner.w - at.x * 1000 }
    end },
    UnitPosition = function()
      if not game.player then return nil end
      return game.player.n, game.player.w, 0, game.player.continent
    end,
    UnitClass = function() return "Warrior", "WARRIOR" end,
    UnitFactionGroup = function() return "Alliance" end,
    QuestDB = game.npcs and { objectives = function(id) return game.questDb[id] or {} end } or nil,
    ItemDB = game.npcs and {
      name = function(id) return game.items[id] and game.items[id].name end,
      npcDrops = function(id) return game.items[id] and game.items[id].drops end,
    } or nil,
    C_QuestLog = {
      GetNumQuestLogEntries = function() return #game.quests + 1 end,
      GetInfo = function(i)
        if i == 1 then return { isHeader = true } end
        return { questID = i, isHeader = false, title = game.titles[i] or ("Quest " .. i) }
      end,
      GetQuestObjectives = function(questID) return game.quests[questID - 1] end,
    },
  }
  local w = wow.load({
    files = { "ForeverUtils/Modules/Finder.lua" },
    env = env,
    db = opts.finder and { modules = { finder = opts.finder } } or opts.db,
  })
  w.game = game
  w.finder = w.ns.finder
  function w:Tf(input) self.env.SlashCmdList.FOREVERUTILSFINDER(input) end
  function w:Macro() return game.macros[1] and game.macros[1].body end
  -- Runs timers until none are left, returning how many ran.
  function w:RunTimers()
    local ran = 0
    while game.timers[1] do
      table.remove(game.timers, 1)()
      ran = ran + 1
    end
    return ran
  end
  function w:Names(query, limit)
    local names = {}
    for i, result in ipairs(self.finder:Search(query, limit or 10)) do
      names[i] = result.name .. " (" .. result.source .. ")"
    end
    return names
  end
  return w
end

local function lines(...) return table.concat({ ... }, "\n") end

describe("the macro", function()
  it("targets a live mob and marks it", function()
    local w = load()
    w:Tf("Black Ooze")
    assert.equal(lines(
      "/cleartarget",
      "/targetexact Black Ooze",
      "/cleartarget [dead]",
      "/tm [exists,nodead] 0", "/tm [exists,nodead] 1"), w:Macro())
    assert.equal("FUFind", w.game.macros[1].name)
  end)

  it("tries each mob in turn until one is found", function()
    local w = load()
    w:Tf("Black Ooze")
    w:Tf("+ Green Ooze")
    assert.equal(lines(
      "/cleartarget",
      "/targetexact Black Ooze",
      "/cleartarget [dead]",
      "/targetexact [noexists] Green Ooze",
      "/cleartarget [dead]",
      "/tm [exists,nodead] 0", "/tm [exists,nodead] 1"), w:Macro())
  end)

  it("can include dead mobs", function()
    local w = load({ finder = { allowDead = true } })
    w:Tf("Black Ooze")
    w:Tf("+ Green Ooze")
    assert.equal(lines(
      "/cleartarget",
      "/targetexact Black Ooze",
      "/targetexact [noexists] Green Ooze",
      "/tm [exists] 0", "/tm [exists] 1"), w:Macro())
  end)

  it("uses the chosen marker, or none", function()
    local w = load({ finder = { marker = 8 } })
    w:Tf("Black Ooze")
    assert.matches("/tm [exists,nodead] 0\n/tm [exists,nodead] 8", w:Macro(), 1, true)
    w.finder.db.marker = 0
    w.finder:Changed()
    assert.is_nil(w:Macro():find("/tm", 1, true))
  end)

  it("can be written for one mob on its own", function()
    local w = load({ finder = { targets = { "Black Ooze", "Green Ooze" } } })
    assert.equal(lines("/cleartarget", "/targetexact Green Ooze", "/cleartarget [dead]",
      "/tm [exists,nodead] 0", "/tm [exists,nodead] 1"),
      w.finder:MacroTextFor("Green Ooze"))
    w.db.modules.finder.allowDead, w.db.modules.finder.marker = true, 0
    assert.equal(lines("/cleartarget", "/targetexact Green Ooze"), w.finder:MacroTextFor("Green Ooze"))
  end)

  it("has a second macro for one mob, leaving the main one alone", function()
    local w = load()
    w.finder:SetTargets({ "Black Ooze", "Green Ooze" })
    local whole = w:Macro()
    assert.is_true(w.finder:Solo("Green Ooze"))
    assert.equal(whole, w:Macro())
    assert.same({ name = "FUFindOne", body = w.finder:MacroTextFor("Green Ooze") }, w.game.macros[2])
    w.finder:Solo("Black Ooze") -- rewritten, not made again
    assert.equal(2, #w.game.macros)
    assert.equal(w.finder:MacroTextFor("Black Ooze"), w.game.macros[2].body)
  end)

  it("leaves the second macro alone in combat, and says so if it can't be made", function()
    local w = load()
    w.finder:SetTargets({ "Black Ooze" })
    w.game.combat = true
    assert.is_false(w.finder:Solo("Black Ooze"))
    assert.equal(1, #w.game.macros)
    w.game.combat, w.game.macroListFull = false, true
    assert.is_false(w.finder:Solo("Black Ooze"))
    assert.matches("couldn't create the FUFindOne macro", w.printed[#w.printed])
  end)

  it("is updated in place, never duplicated", function()
    local w = load()
    w:Tf("Black Ooze")
    w:Tf("Green Ooze")
    assert.equal(1, #w.game.macros)
    assert.matches("Green Ooze", w:Macro())
    assert.is_nil(w:Macro():find("Black Ooze"))
  end)

  it("opens the window when there's nothing to find", function()
    local w = load()
    w:Tf("Black Ooze")
    w:Tf("clear")
    assert.equal("/tf", w:Macro())
  end)

  it("isn't created until you pick something", function()
    local w = load()
    w:Fire("PLAYER_ENTERING_WORLD")
    w:Tf("clear")
    assert.same({}, w.game.macros)
  end)

  it("isn't created at login, when the macro list may not have loaded", function()
    local w = load({ finder = { targets = { "Black Ooze" } } })
    w:Fire("PLAYER_ENTERING_WORLD")
    assert.same({}, w.game.macros)
  end)

  it("is refreshed at login if it exists", function()
    local w = load({ finder = { targets = { "Black Ooze" } } })
    w.game.macros[1] = { name = "FUFind", body = "stale" }
    w:Fire("PLAYER_ENTERING_WORLD")
    assert.matches("/targetexact Black Ooze", w:Macro(), 1, true)
  end)

  it("stays within 255 characters, leaving out the mobs that don't fit", function()
    local w = load()
    local names = {}
    for i = 1, 8 do names[i] = "A Rather Long Mob Name " .. i end
    w.finder:SetTargets(names)
    local text, used = w.finder:MacroText()
    assert.is_true(#text <= 255)
    assert.is_true(used >= 3 and used < 8)
    assert.matches("Mob Name " .. used, text, 1, true)
    assert.is_nil(text:find("Mob Name " .. used + 1, 1, true))
    assert.matches("/tm %[exists,nodead%] 0\n/tm %[exists,nodead%] 1$", text)
    assert.equal(8, #w.finder.db.targets)
  end)

  it("waits for combat to end before changing", function()
    local w = load()
    w:Tf("Black Ooze")
    w.game.combat = true
    w:Tf("Green Ooze")
    assert.matches("Black Ooze", w:Macro())
    w.game.combat = false
    w:Fire("PLAYER_REGEN_ENABLED")
    assert.matches("Green Ooze", w:Macro())
  end)

  it("is created after combat if first asked for during it", function()
    local w = load()
    w.game.combat = true
    w:Tf("Black Ooze")
    assert.same({}, w.game.macros)
    w.game.combat = false
    w:Fire("PLAYER_REGEN_ENABLED")
    assert.matches("Black Ooze", w:Macro())
  end)

  it("says so when the macro list is full", function()
    local w = load()
    w.game.macroListFull = true
    w:Tf("Black Ooze")
    assert.matches("couldn't create the FUFind macro", w.printed[1], 1, true)
    assert.same({ "Black Ooze" }, w.finder.db.targets)
  end)
end)

describe("the find list", function()
  it("keeps macro syntax out of names", function()
    local w = load()
    w:Tf("  Black;   Ooze [dead]\n/quit ")
    assert.same({ "Black Ooze dead /quit" }, w.finder.db.targets)
  end)

  it("doesn't add the same mob twice", function()
    local w = load()
    w:Tf("Black Ooze")
    w:Tf("+ black ooze")
    w:Tf("add Green Ooze")
    assert.same({ "Black Ooze", "Green Ooze" }, w.finder.db.targets)
  end)

  it("moves a mob up or down the order the macro tries them in", function()
    local w = load()
    w.finder:SetTargets({ "Black Ooze", "Green Ooze", "Kobold" })
    assert.is_true(w.finder:Move("kobold", -1))
    assert.same({ "Black Ooze", "Kobold", "Green Ooze" }, w.db.modules.finder.targets)
    assert.matches("/targetexact Black Ooze.+/targetexact %[noexists%] Kobold.+Green Ooze", w:Macro())
    assert.is_true(w.finder:Move("Black Ooze", 1))
    assert.same({ "Kobold", "Black Ooze", "Green Ooze" }, w.db.modules.finder.targets)
    assert.is_false(w.finder:Move("Kobold", -1))     -- already first
    assert.is_false(w.finder:Move("Green Ooze", 1))  -- already last
    assert.is_false(w.finder:Move("Nobody", 1))
    assert.same({ "Kobold", "Black Ooze", "Green Ooze" }, w.db.modules.finder.targets)
  end)

  it("keeps a history of the last ten mobs found, newest first", function()
    local w = load()
    w.finder:SetTargets({ "Black Ooze", "Green Ooze" })
    w.finder:Add("Kobold")
    w.finder:Remove("Kobold")
    w.finder:SetTargets({ "green ooze" }) -- found again: moves to the front, isn't repeated
    assert.same({ "Green Ooze", "Kobold", "Black Ooze" }, w.db.modules.finder.history)
    for i = 1, 12 do w.finder:SetTargets({ "Mob " .. i }) end
    assert.equal(10, #w.db.modules.finder.history)
    assert.equal("Mob 12", w.db.modules.finder.history[1])
    assert.equal("Mob 3", w.db.modules.finder.history[10])
  end)

  it("removes a mob by name", function()
    local w = load()
    w.finder:SetTargets({ "Black Ooze", "Green Ooze" })
    w:Tf("- BLACK OOZE")
    assert.same({ "Green Ooze" }, w.finder.db.targets)
    w:Tf("remove Nobody")
    assert.matches("Nobody isn't on the find list", w.printed[#w.printed], 1, true)
  end)

  it("uses the game's spelling of a mob it knows", function()
    local w = load({ finder = { seen = { ["Black Ooze"] = 5 } } })
    w:Tf("black ooze")
    assert.same({ "Black Ooze" }, w.finder.db.targets)
  end)

  it("/tf hover finds the mob under the cursor, then your target", function()
    local w = load()
    w.game.units.target = { name = "Green Ooze" }
    w:Tf("hover")
    assert.same({ "Green Ooze" }, w.finder.db.targets)
    w.game.units.mouseover = { name = "Black Ooze" }
    w.env.ForeverUtils_FindHover()
    assert.same({ "Black Ooze" }, w.finder.db.targets)
  end)

  it("can add a unit to the list instead of replacing it", function()
    local w = load({ finder = { targets = { "Black Ooze" } } })
    w.game.units.target = { name = "Green Ooze" }
    assert.is_true(w.finder:UseUnit("target", true))
    assert.same({ "Black Ooze", "Green Ooze" }, w.finder.db.targets)
    assert.is_true(w.finder:UseUnit("target"))
    assert.same({ "Green Ooze" }, w.finder.db.targets)
    assert.is_false(w.finder:UseUnit("mouseover"))
  end)

  it("offers finding for mobs, not players or nothing", function()
    local w = load()
    assert.is_false(w.finder:CanFind("target"))
    w.game.units.target = { name = "Green Ooze" }
    assert.is_true(w.finder:CanFind("target"))
    w.game.units.target = { name = "Bob", player = true }
    assert.is_false(w.finder:CanFind("target"))
  end)

  it("/tf hover with nothing there changes nothing", function()
    local w = load({ finder = { targets = { "Black Ooze" } } })
    w:Tf("hover")
    assert.same({ "Black Ooze" }, w.finder.db.targets)
    assert.matches("hover over or target a mob first", w.printed[1], 1, true)
  end)

  it("/tf list shows what's being found", function()
    local w = load({ finder = { targets = { "Black Ooze", "Green Ooze" } } })
    w:Tf("list")
    assert.matches("finding: Black Ooze, Green Ooze", w.printed[1], 1, true)
  end)

  it("does nothing while the module is off", function()
    local w = load({ finder = { enabled = false } })
    w:Tf("Black Ooze")
    w.game.units.mouseover = { name = "Black Ooze" }
    w.env.ForeverUtils_FindHover()
    assert.same({}, w.finder.db.targets)
    assert.matches("Target Finder is off", w.printed[1], 1, true)
  end)
end)

describe("suggestions", function()
  it("remembers mobs you hover, target or see nameplates for", function()
    local w = load()
    w.game.units.mouseover = { name = "Black Ooze" }
    w:Fire("UPDATE_MOUSEOVER_UNIT")
    w.game.now = 1001
    w.game.units.target = { name = "Green Ooze" }
    w:Fire("PLAYER_TARGET_CHANGED")
    w.game.now = 1002
    w.game.units.nameplate3 = { name = "Red Ooze" }
    w:Fire("NAME_PLATE_UNIT_ADDED", "nameplate3")
    assert.same({ "Red Ooze (seen)", "Green Ooze (seen)", "Black Ooze (seen)" }, w:Names(""))
  end)

  it("ignores units whose names the game withholds, as in instances", function()
    local w = load({ finder = { targets = { "Kobold" } } })
    w.game.units.mouseover = { name = w.game.secret }
    w.game.units.target = { name = w.game.secret }
    w.game.units.nameplate1 = { name = "Rat", player = w.game.secret }
    w:Fire("UPDATE_MOUSEOVER_UNIT")
    w:Fire("PLAYER_TARGET_CHANGED")
    w:Fire("NAME_PLATE_UNIT_ADDED", "nameplate1")
    assert.same({}, w.db.modules.finder.seen)
    assert.is_false(w.finder:CanFind("target"))
    assert.is_nil(w.finder:TooltipText(w.game.secret))
    w:Tf("hover")
    assert.same({ "Kobold" }, w.db.modules.finder.targets)
    assert.same({}, w.ns.errors)
  end)

  it("doesn't remember players or their pets", function()
    local w = load()
    w.game.units.mouseover = { name = "Bob", player = true, controlled = true }
    w:Fire("UPDATE_MOUSEOVER_UNIT")
    w.game.units.target = { name = "Bob's Wolf", controlled = true }
    w:Fire("PLAYER_TARGET_CHANGED")
    w.game.units.target = nil
    w:Fire("PLAYER_TARGET_CHANGED")
    assert.same({}, w:Names(""))
  end)

  it("reads mob names from unfinished kill objectives, in either format", function()
    local w = load()
    w.game.quests = {
      {
        { type = "monster", text = "Black Ooze slain: 3/10" },
        { type = "item", text = "Ooze Sample: 0/5" },
        { type = "monster", text = "10/10 Green Ooze slain", finished = true },
      },
      { { type = "monster", text = "0/1 Speak with Bob killed" }, { type = "monster", text = "2/8 Red Ooze" } },
    }
    assert.same({ "Black Ooze (quest)", "Red Ooze (quest)", "Speak with Bob (quest)" }, w:Names(""))
  end)

  it("rereads the quest log when it changes", function()
    local w = load()
    assert.same({}, w:Names(""))
    w.game.quests = { { { type = "monster", text = "Black Ooze slain: 0/4" } } }
    assert.same({}, w:Names(""))
    w:Fire("QUEST_LOG_UPDATE")
    assert.same({ "Black Ooze (quest)" }, w:Names(""))
  end)

  it("matches any part of the name, ignoring case, quest mobs first", function()
    local w = load({ finder = { seen = { ["Green Ooze"] = 9, ["Black Ooze"] = 5, ["Kobold"] = 7 } } })
    w.game.quests = { { { type = "monster", text = "Black Ooze slain: 0/4" } } }
    assert.same({ "Black Ooze (quest)", "Green Ooze (seen)" }, w:Names(" OOZ "))
    assert.same({ "Kobold (seen)" }, w:Names("kob"))
    assert.same({}, w:Names("murloc"))
  end)

  it("leaves out mobs already on the list, and stops at the limit", function()
    local w = load({ finder = { targets = { "Black Ooze" }, seen = { ["Black Ooze"] = 5, A = 4, B = 3, C = 2 } } })
    assert.same({ "A (seen)", "B (seen)" }, w:Names("", 2))
  end)

  it("forgets the mobs seen longest ago", function()
    local seen = {}
    for i = 1, 320 do seen["Mob " .. i] = i end
    local w = load({ finder = { seen = seen } })
    local count = 0
    for _ in pairs(w.finder.db.seen) do count = count + 1 end
    assert.equal(300, count)
    assert.is_nil(w.finder.db.seen["Mob 20"])
    assert.equal(21, w.finder.db.seen["Mob 21"])
  end)
end)

describe("the QuestieDB mob list", function()
  local NPCS = {
    [1] = "Black Ooze", [2] = "Blackrock Grunt", [3] = "Green Ooze", [4] = "Black Ooze",
    [5] = "Ooze Covered Bag", [6] = "", [7] = "error", [9] = "Kobold",
  }

  it("is searched once you type something, names starting with it first", function()
    local w = load({ npcs = NPCS })
    w.finder:LoadDatabase()
    assert.equal("ready", w.finder:DatabaseState())
    assert.same({}, w:Names(""))
    assert.same({ "Ooze Covered Bag (database)", "Black Ooze (database)", "Green Ooze (database)" }, w:Names("ooze"))
    assert.same({ "Black Ooze (database)", "Blackrock Grunt (database)" }, w:Names("BLACK"))
  end)

  it("comes after quest mobs and mobs you've seen, without repeating them", function()
    local w = load({ npcs = NPCS, finder = { seen = { ["Green Ooze"] = 5 }, targets = { "Black Ooze" } } })
    w.finder:LoadDatabase()
    assert.same({ "Green Ooze (seen)", "Ooze Covered Bag (database)" }, w:Names("ooze"))
    assert.same({ "Green Ooze (seen)" }, w:Names("ooze", 1))
  end)

  it("gives typed names the game's spelling", function()
    local w = load({ npcs = NPCS })
    w.finder:LoadDatabase()
    w:Tf("blackrock grunt")
    assert.same({ "Blackrock Grunt" }, w.finder.db.targets)
  end)

  it("loads a batch per frame", function()
    local npcs = {}
    for i = 1, 1200 do npcs[i] = "Mob " .. i end
    local w = load({ npcs = npcs })
    w.finder:LoadDatabase()
    assert.equal("loading", w.finder:DatabaseState())
    assert.same({}, w:Names("mob 1200"))
    w.finder:LoadDatabase() -- a second call while loading starts nothing new
    assert.equal(2, w:RunTimers())
    assert.equal("ready", w.finder:DatabaseState())
    assert.same({ "Mob 1200 (database)" }, w:Names("mob 1200"))
  end)

  it("isn't read until asked for", function()
    local w = load({ npcs = NPCS })
    assert.equal("idle", w.finder:DatabaseState())
    assert.same({}, w:Names("ooze"))
  end)

  it("is skipped when QuestieDB isn't installed", function()
    local w = load({ finder = { seen = { ["Green Ooze"] = 5 } } })
    w.finder:LoadDatabase()
    assert.equal("missing", w.finder:DatabaseState())
    assert.same({ "Green Ooze (seen)" }, w:Names("ooze"))
  end)
end)

describe("the tooltip line", function()
  it("says a mob is the only one you're finding", function()
    local w = load({ finder = { targets = { "Black Ooze" } } })
    assert.equal("Target Finder: the only mob you're finding", w.finder:TooltipText("black ooze"))
  end)

  it("says where a mob is on a longer list", function()
    local w = load({ finder = { targets = { "Black Ooze", "Green Ooze", "Red Ooze" } } })
    assert.equal("Target Finder: finding, 2 of 3 on your list", w.finder:TooltipText("Green Ooze"))
  end)

  it("says when a mob is on the list but left out of the macro", function()
    local names = {}
    for i = 1, 8 do names[i] = "A Rather Long Mob Name " .. i end
    local w = load({ finder = { targets = names } })
    assert.matches("finding, 1 of 8", w.finder:TooltipText(names[1]), 1, true)
    assert.matches("doesn't fit in the macro", w.finder:TooltipText(names[8]), 1, true)
  end)

  it("is absent for other mobs, and for nothing at all", function()
    local w = load({ finder = { targets = { "Black Ooze" } } })
    assert.is_nil(w.finder:TooltipText("Kobold"))
    assert.is_nil(w.finder:TooltipText(nil))
    assert.is_nil(w.finder:TooltipText(""))
  end)
end)

describe("the window's list", function()
  -- Rows as text, indented two spaces a level: "+ Title (n)" for a closed section, "- Title (n)" for an open one,
  -- "  Name [note]" for a mob, with * after mobs already on the find list.
  local function rows(w, query, expanded)
    local out = {}
    for i, entry in ipairs(w.finder:Browse(query, expanded or {}, 10)) do
      if entry.kind == "header" then
        out[i] = ("%s%s %s (%d)"):format(("  "):rep(entry.level), entry.open and "-" or "+", entry.title, entry.count)
      else
        out[i] = ("  "):rep((entry.level or 0) + 1) .. entry.name
          .. (entry.note and " [" .. entry.note .. "]" or "") .. (entry.listed and " *" or "")
      end
    end
    return out
  end

  local function quests(w)
    -- Quest ids are 2 and 3: the fake quest log's first entry is a zone header.
    w.game.quests = {
      { { type = "monster", text = "Black Ooze slain: 3/10" }, { type = "monster", text = "Green Ooze slain: 0/4" } },
      { { type = "item", text = "Kobold Candle: 0/8" } },
    }
    w.game.titles = { [2] = "Ooze Trouble", [3] = "Candles" }
    w:Fire("QUEST_LOG_UPDATE")
  end

  it("starts with Quests and recently seen mobs, both closed", function()
    local w = load({ finder = { seen = { Kobold = 5 } } })
    quests(w)
    assert.same({ "+ Quests (1)", "+ Recently seen mobs (1)" }, rows(w, ""))
  end)

  it("shows every quest and its mobs once Quests is opened, and remembers what you close", function()
    local w = load({ finder = { seen = { Kobold = 5 }, targets = { "Green Ooze" } } })
    quests(w)
    assert.same({ "- Quests (1)", "  - Ooze Trouble (2)", "    Black Ooze", "    Green Ooze *",
      "+ Recently seen mobs (1)" }, rows(w, " ", { quests = true }))
    assert.same({ "- Quests (1)", "  + Ooze Trouble (2)", "- Recently seen mobs (1)", "  Kobold" },
      rows(w, "", { quests = true, quest2 = false, seen = true }))
  end)

  it("gives a section every mob name, to find them all at once", function()
    local w = load()
    quests(w)
    assert.same({ "Black Ooze", "Green Ooze" }, w.finder:Browse("", { quests = true }, 10)[2].names)
  end)

  it("lists the history after the quests, marking mobs still being found", function()
    local w = load()
    w.finder:SetTargets({ "Black Ooze" })
    w.finder:SetTargets({ "Kobold" })
    assert.same({ "+ History (2)" }, rows(w, ""))
    assert.same({ "- History (2)", "  Kobold *", "  Black Ooze" }, rows(w, "", { history = true }))
  end)

  it("shows search results instead while something is typed", function()
    local w = load({ finder = { seen = { Kobold = 5 } } })
    quests(w)
    assert.same({ "  Black Ooze [quest]", "  Green Ooze [quest]" }, rows(w, "ooze", { quest2 = true }))
  end)

  it("leaves out finished quests", function()
    local w = load()
    w.game.quests = { { { type = "monster", text = "Black Ooze slain: 10/10", finished = true } } }
    w:Fire("QUEST_LOG_UPDATE")
    assert.same({}, rows(w, ""))
  end)

  describe("with QuestieDB", function()
    local NPCS = { [10] = "Kobold Miner", [11] = "Kobold Digger", [12] = "Black Ooze", [13] = "Ooze Lord" }
    local QUEST_DB = {
      [2] = { [1] = { { 12 } }, [5] = { { { 13, 12 }, 13 } } },
      [3] = { [3] = { { 500 } } },
    }
    local ITEMS = { [500] = { name = "Kobold Candle", drops = { 11, 10 } } }

    it("lists the mobs to kill and the mobs that drop quest items", function()
      local w = load({ npcs = NPCS, questDb = QUEST_DB, items = ITEMS })
      quests(w)
      assert.same({
        "- Quests (2)",
        "  - Ooze Trouble (2)", "    Black Ooze", "    Ooze Lord",
        "  - Candles (2)", "    Kobold Digger [Kobold Candle]", "    Kobold Miner [Kobold Candle]",
      }, rows(w, "", { quests = true }))
    end)

    it("offers those mobs when searching, too", function()
      local w = load({ npcs = NPCS, questDb = QUEST_DB, items = ITEMS })
      quests(w)
      assert.same({ "Kobold Digger (quest)", "Kobold Miner (quest)" }, w:Names("kob"))
    end)

    it("falls back to the objective text for a quest it doesn't know", function()
      local w = load({ npcs = NPCS, questDb = {}, items = ITEMS })
      quests(w)
      assert.same({ "- Quests (1)", "  - Ooze Trouble (2)", "    Black Ooze", "    Green Ooze" },
        rows(w, "", { quests = true }))
    end)
  end)
end)

describe("the nearest service", function()
  local VENDOR, TRAINER, BANKER, REPAIR = 4, 16, 256, 16384
  local NPCS = {
    [1] = "Near Vendor", [2] = "Far Smith", [3] = "Near Smith", [4] = "Horde Smith", [5] = "Abroad Smith",
    [6] = "Warrior Guy", [7] = "Mage Guy", [8] = "Herb Lady", [9] = "Plain Mob", [10] = "Dungeon Banker",
  }
  -- Spawns are map percentages. You stand at the bottom right corner of area 12's map,
  -- so { 90, 100 } is 100 yards west of you and { 100, 50 } is 500 yards north.
  local INFO = {
    [1] = { flags = VENDOR, faction = "AH", spawns = { [12] = { { 95, 100 } } } },
    [2] = { flags = VENDOR + REPAIR, title = "Weaponsmith", faction = "A", spawns = { [12] = { { 100, 50 } } } },
    [3] = { flags = VENDOR + REPAIR, title = "Armorer", faction = "A", spawns = { [14] = { { 90, 90 } } } },
    [4] = { flags = VENDOR + REPAIR, faction = "H", spawns = { [12] = { { 99, 99 } } } },
    [5] = { flags = VENDOR + REPAIR, faction = "A", spawns = { [17] = { { 100, 100 } } } },
    [6] = { flags = TRAINER, title = "Warrior Trainer", faction = "A", spawns = { [12] = { { 100, 80 } } } },
    [7] = { flags = TRAINER, title = "Mage Trainer", faction = "A", spawns = { [12] = { { 100, 99 } } } },
    [8] = { flags = TRAINER, title = "Herbalism Trainer", faction = "A", spawns = { [12] = { { 80, 100 } } } },
    [9] = { flags = 0, spawns = { [12] = { { 100, 100 } } } },
    [10] = { flags = BANKER, faction = "AH", spawns = { [12] = { { -1, -1 } } } },
  }

  local function ready(opts)
    opts = opts or {}
    opts.npcs, opts.npcInfo = opts.npcs or NPCS, opts.npcInfo or INFO
    local w = load(opts)
    w.finder:LoadDatabase()
    w:RunTimers()
    return w
  end

  it("goes on the find list, with how far and which way", function()
    local w = ready({ finder = { targets = { "Kobold" } } })
    w.finder:FindNearest("repair")
    assert.same({ "Near Smith" }, w.db.modules.finder.targets)
    assert.matches("nearest repair: Near Smith <Armorer>, 141 yards north%-west", w.printed[#w.printed])
  end)

  it("is the closest one of any that sell", function()
    local w = ready()
    w.finder:FindNearest("vendor")
    assert.same({ "Near Vendor" }, w.db.modules.finder.targets)
    assert.matches("50 yards west", w.printed[#w.printed])
  end)

  it("changes as you move", function()
    local w = ready()
    w.game.player = { n = 500, w = 0, continent = 0 }
    w.finder:FindNearest("repair")
    assert.same({ "Far Smith" }, w.db.modules.finder.targets)
  end)

  it("leaves out the other faction's, and other continents'", function()
    local w = ready()
    local found = w.finder:NearestServices()
    assert.equal("Near Smith", found.repair.name)
    w.game.player = { n = 0, w = 0, continent = 1 }
    assert.equal("Abroad Smith", w.finder:NearestServices().repair.name)
  end)

  it("picks your own class's trainer", function()
    local w = ready()
    w.finder:FindNearest("class")
    assert.same({ "Warrior Guy" }, w.db.modules.finder.targets)
  end)

  it("picks profession trainers by their title", function()
    local w = ready()
    local found = w.finder:NearestServices()
    assert.equal("Herb Lady", found.herbalism.name)
    assert.is_nil(found.mining)
  end)

  it("says so when there's none it knows where to find", function()
    local w = ready({ finder = { targets = { "Kobold" } } })
    w.finder:FindNearest("banker") -- the only one is inside an instance
    assert.same({ "Kobold" }, w.db.modules.finder.targets)
    assert.matches("doesn't know a banker", w.printed[#w.printed])
  end)

  it("says so where the game won't say where you are", function()
    local w = ready()
    w.game.player = nil
    w.finder:FindNearest("repair")
    assert.same({}, w.db.modules.finder.targets)
    assert.matches("doesn't say where you are", w.printed[#w.printed])
  end)

  it("needs QuestieDB, and its zone maps", function()
    local w = load()
    w.finder:FindNearest("repair")
    assert.matches("needs the QuestieDB addon", w.printed[#w.printed])
    w = ready({ noZones = true })
    w.finder:FindNearest("repair")
    assert.matches("needs the QuestieDB addon", w.printed[#w.printed])
  end)

  it("is found once the NPC list has loaded, if asked for sooner", function()
    local npcs, npcInfo = {}, {}
    for id = 1, 1200 do npcs[id] = "Mob " .. id end
    npcs[1200], npcInfo[1200] = "Late Smith", INFO[3]
    local w = load({ npcs = npcs, npcInfo = npcInfo })
    w.finder:FindNearest("repair")
    assert.same({}, w.db.modules.finder.targets)
    assert.matches("one moment", w.printed[#w.printed])
    w:RunTimers()
    assert.same({ "Late Smith" }, w.db.modules.finder.targets)
  end)

  it("/tf nearest finds one, or lists what it can find", function()
    local w = ready()
    w:Tf("nearest Repair")
    assert.same({ "Near Smith" }, w.db.modules.finder.targets)
    w:Tf("nearest pizza")
    assert.matches("/tf nearest <one of: vendor, repair, banker", w.printed[#w.printed])
    assert.same({ "Near Smith" }, w.db.modules.finder.targets)
  end)

  it("is listed in the window, services and profession trainers apart", function()
    local w = ready({ finder = { targets = { "Near Vendor" } } })
    local out = {}
    for i, entry in ipairs(w.finder:Browse("", { services = true }, 10)) do
      out[i] = entry.kind == "header" and ("%s (%d)"):format(entry.title, entry.count)
        or ("  %s [%s]%s"):format(entry.label, entry.note, entry.listed and " *" or "")
    end
    assert.same({
      "Nearest services (3)",
      "  Vendor: Near Vendor [50 yd] *",
      "  Repair: Near Smith [141 yd]",
      "  Class trainer: Warrior Guy [200 yd]",
      "Nearest profession trainers (1)",
    }, out)
  end)

  it("isn't listed in the window where the game won't say where you are", function()
    local w = ready()
    w.game.player = nil
    assert.same({}, w.finder:Browse("", { services = true }, 10))
  end)
end)

describe("minimap pins", function()
  local NPCS = { [1] = "Black Ooze", [2] = "Black Ooze", [3] = "Green Ooze", [4] = "Abroad Ooze" }
  -- You stand at the bottom right corner of area 12's map: { 90, 100 } is 100 yards west.
  local INFO = {
    [1] = { spawns = { [12] = { { 90, 100 }, { 100, 95 } } } },
    [2] = { spawns = { [12] = { { 100, 60 } }, [99] = { { 50, 50 } } } },
    [3] = { spawns = { [12] = { { 98, 100 } } } },
    [4] = { spawns = { [17] = { { 100, 100 } } } },
  }

  local function ready(targets)
    local w = load({ npcs = NPCS, npcInfo = INFO, finder = { targets = targets } })
    w.finder:LoadDatabase()
    w:RunTimers()
    return w
  end

  -- Pins as "x,y" in tenths of the minimap's radius, with ! for one pushed to the rim.
  local function pins(w, radius, facing, limit)
    local out = {}
    for i, pin in ipairs(w.finder:MinimapPins(radius, facing, limit or 10)) do
      out[i] = ("%d,%d%s"):format(math.floor(pin.x * 10 + 0.5), math.floor(pin.y * 10 + 0.5), pin.edge and "!" or "")
    end
    return out
  end

  it("show the spawn points in range, nearest first, for every mob of that name", function()
    local w = ready({ "Black Ooze" })
    assert.same({ "0,3", "-5,0" }, pins(w, 200))
    assert.same({ "0,1", "-2,0", "0,8" }, pins(w, 500))
  end)

  it("cover every mob on the find list", function()
    local w = ready({ "Black Ooze", "Green Ooze" })
    assert.same({ "-1,0", "0,3", "-5,0" }, pins(w, 200))
  end)

  it("stop at the limit", function()
    local w = ready({ "Black Ooze", "Green Ooze" })
    assert.same({ "-1,0", "0,3" }, pins(w, 200, nil, 2))
  end)

  it("put the nearest one on the rim when none is in range", function()
    local w = ready({ "Black Ooze" })
    assert.same({ "0,10!" }, pins(w, 40))
  end)

  it("turn with you when the minimap rotates", function()
    local w = ready({ "Black Ooze" })
    assert.same({ "3,0", "0,5" }, pins(w, 200, math.pi / 2)) -- facing west: north is to your right
  end)

  it("follow the find list", function()
    local w = ready({ "Black Ooze" })
    w.finder:SetTargets({ "Green Ooze" })
    assert.same({ "-1,0" }, pins(w, 200))
    w.finder:SetTargets({})
    assert.same({}, pins(w, 200))
  end)

  it("are absent on another continent, or where the game won't say where you are", function()
    local w = ready({ "Abroad Ooze" })
    assert.same({}, pins(w, 200))
    w.game.player = { n = 0, w = 0, continent = 1 }
    assert.same({ "0,0" }, pins(w, 200))
    w.game.player = nil
    assert.same({}, pins(w, 200))
  end)

  it("read QuestieDB's NPC list themselves if nothing else has", function()
    local w = load({ npcs = NPCS, npcInfo = INFO, finder = { targets = { "Green Ooze" } } })
    assert.same({ "-1,0" }, pins(w, 200))
  end)

  it("are absent without QuestieDB", function()
    local w = load({ finder = { targets = { "Green Ooze" } } })
    assert.same({}, pins(w, 200))
  end)
end)
