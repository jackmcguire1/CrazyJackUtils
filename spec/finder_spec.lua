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
  }
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
    } or nil,
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
      "/tm [exists,nodead] 1"), w:Macro())
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
      "/tm [exists,nodead] 1"), w:Macro())
  end)

  it("can include dead mobs", function()
    local w = load({ finder = { allowDead = true } })
    w:Tf("Black Ooze")
    w:Tf("+ Green Ooze")
    assert.equal(lines(
      "/cleartarget",
      "/targetexact Black Ooze",
      "/targetexact [noexists] Green Ooze",
      "/tm [exists] 1"), w:Macro())
  end)

  it("uses the chosen marker, or none", function()
    local w = load({ finder = { marker = 8 } })
    w:Tf("Black Ooze")
    assert.matches("/tm [exists,nodead] 8", w:Macro(), 1, true)
    w.finder.db.marker = 0
    w.finder:Changed()
    assert.is_nil(w:Macro():find("/tm", 1, true))
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
    assert.matches("/tm %[exists,nodead%] 1$", text)
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
  -- Rows as text: "+ Title (n)" for a closed section, "- Title (n)" for an open one,
  -- "  Name [note]" for a mob, with * after mobs already on the find list.
  local function rows(w, query, expanded)
    local out = {}
    for i, entry in ipairs(w.finder:Browse(query, expanded or {}, 10)) do
      if entry.kind == "header" then
        out[i] = ("%s %s (%d)"):format(entry.open and "-" or "+", entry.title, #entry.names)
      else
        out[i] = "  " .. entry.name .. (entry.note and " [" .. entry.note .. "]" or "") .. (entry.listed and " *" or "")
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

  it("shows each quest as a closed section, then recently seen mobs", function()
    local w = load({ finder = { seen = { Kobold = 5 } } })
    quests(w)
    assert.same({ "+ Ooze Trouble (2)", "+ Recently seen (1)" }, rows(w, ""))
  end)

  it("lists a section's mobs once it's opened, marking ones already being found", function()
    local w = load({ finder = { seen = { Kobold = 5 }, targets = { "Green Ooze" } } })
    quests(w)
    assert.same({ "- Ooze Trouble (2)", "  Black Ooze", "  Green Ooze *", "+ Recently seen (1)" },
      rows(w, " ", { quest2 = true }))
    assert.same({ "+ Ooze Trouble (2)", "- Recently seen (1)", "  Kobold" }, rows(w, "", { seen = true }))
  end)

  it("gives a section every mob name, to find them all at once", function()
    local w = load()
    quests(w)
    assert.same({ "Black Ooze", "Green Ooze" }, w.finder:Browse("", {}, 10)[1].names)
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
        "- Ooze Trouble (2)", "  Black Ooze", "  Ooze Lord",
        "- Candles (2)", "  Kobold Digger [Kobold Candle]", "  Kobold Miner [Kobold Candle]",
      }, rows(w, "", { quest2 = true, quest3 = true }))
    end)

    it("offers those mobs when searching, too", function()
      local w = load({ npcs = NPCS, questDb = QUEST_DB, items = ITEMS })
      quests(w)
      assert.same({ "Kobold Digger (quest)", "Kobold Miner (quest)" }, w:Names("kob"))
    end)

    it("falls back to the objective text for a quest it doesn't know", function()
      local w = load({ npcs = NPCS, questDb = {}, items = ITEMS })
      quests(w)
      assert.same({ "- Ooze Trouble (2)", "  Black Ooze", "  Green Ooze" }, rows(w, "", { quest2 = true }))
    end)
  end)
end)
