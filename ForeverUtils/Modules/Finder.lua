local _, ns = ...

-- Target Finder: keeps a macro that targets the mobs on your list. Addons can't target
-- units themselves, so the macro (and the button in FinderUI.lua that runs it) does it.

local MACRO_NAME = "FUFind"
local MACRO_ICON = "INV_MISC_QUESTIONMARK" -- shows the icon of whatever the macro would do
local MACRO_LIMIT = 255
local EMPTY_MACRO = "/tf" -- with nothing to find, the macro opens the window instead
local SEEN_LIMIT = 300
local DATABASE_BATCH = 500 -- names read per frame while loading QuestieDB's NPC list

local module = ns.RegisterModule({
  key = "finder",
  name = "Target Finder",
  description = "Keeps a macro and a button that target the mobs you pick. /tf opens it.",
  defaults = {
    targets = {},      -- names, in the order the macro tries them
    seen = {},         -- [npc name] = time() it was last seen, for search suggestions
    allowDead = false, -- also target corpses
    marker = 1,        -- raid marker put on the mob found, 0 for none
    showButton = true, -- the floating button
    tooltip = true,    -- say so on the tooltip of a mob that's on the list
    targetButton = true, -- the Find button on the target frame
    targetMenu = true,   -- the entries in the target's right-click menu
    expanded = {},       -- [section key] = true for sections left open in the window
  },
})
ns.finder = module
module.MACRO_NAME = MACRO_NAME

local questGroups -- cached quests and their mobs; nil when the quest log has changed
local questNames  -- cached list of every mob name in questGroups
local SEEN_SHOWN = 30 -- how many recently seen mobs the window lists

-- Every NPC name from the QuestieDB addon, if it's installed (## OptionalDeps in the TOC).
local databaseState = "idle" -- idle | loading | ready | missing
local databaseLower = {}     -- lowercased names, sorted once loaded
local databaseNames = {}     -- [lowercased name] = name

local function IsSecret(value)
  return issecretvalue and issecretvalue(value)
end

-- A name safe to put in a macro: no macro syntax, tidy spacing. nil if nothing is left.
local function Clean(name)
  if type(name) ~= "string" or IsSecret(name) then return nil end
  name = name:gsub("[%[%];\r\n]", " "):gsub("%s+", " "):match("^ ?(.-) ?$")
  if name == "" then return nil end
  return name
end

---------------------------------------------------------------------------
-- The macro
---------------------------------------------------------------------------

-- The macro body, and how many of the targets fit in it.
function module:MacroText()
  local db = self.db
  local mark = db.marker > 0
    and ("/tm [exists%s] %d"):format(db.allowDead and "" or ",nodead", db.marker) or nil
  -- Clearing first means a miss leaves you with no target, not the old one marked.
  local lines, used = { "/cleartarget" }, 0
  for i, name in ipairs(db.targets) do
    local added = { "/targetexact " .. (i > 1 and "[noexists] " or "") .. name }
    if not db.allowDead then added[2] = "/cleartarget [dead]" end
    local length = #table.concat(lines, "\n") + 1 + #table.concat(added, "\n") + (mark and #mark + 1 or 0)
    if length > MACRO_LIMIT then break end
    for _, line in ipairs(added) do table.insert(lines, line) end
    used = i
  end
  if used == 0 then return EMPTY_MACRO, 0 end
  if mark then table.insert(lines, mark) end
  return table.concat(lines, "\n"), used
end

-- Writes the macro. Macros can't be changed in combat, so that waits until it ends.
-- create: make the macro if it doesn't exist. Never done at login, when the macro list
-- may not have loaded and a second copy would be made.
function module:Sync(create)
  self.pendingCreate = self.pendingCreate or create
  if InCombatLockdown() then
    self.dirty = true
    return
  end
  create, self.pendingCreate, self.dirty = self.pendingCreate, nil, nil
  local text = self:MacroText()
  local index = GetMacroIndexByName(MACRO_NAME)
  if index and index > 0 then
    EditMacro(index, nil, nil, text)
  elseif create then
    local ok, result = pcall(CreateMacro, MACRO_NAME, MACRO_ICON, text, nil)
    if not ok or not result then
      ns.Print("couldn't create the %s macro - is your general macro list full?", MACRO_NAME)
    end
  end
  ns.Debug("macro: %s", (text:gsub("\n", " | ")))
end

local function Changed(self)
  self:Sync(#self.db.targets > 0)
  if self.UpdateUI then self.UpdateUI() end
end
module.Changed = Changed

---------------------------------------------------------------------------
-- The target list
---------------------------------------------------------------------------

local function IndexOf(list, name)
  name = name:lower()
  for i, other in ipairs(list) do
    if other:lower() == name then return i end
  end
end

function module:SetTargets(names)
  local targets = {}
  for _, name in ipairs(names) do
    name = Clean(name)
    if name and not IndexOf(targets, name) then table.insert(targets, self:KnownName(name)) end
  end
  self.db.targets = targets
  Changed(self)
end

function module:Add(name)
  name = Clean(name)
  if not name or IndexOf(self.db.targets, name) then return end
  table.insert(self.db.targets, self:KnownName(name))
  Changed(self)
end

function module:Remove(name)
  local index = Clean(name) and IndexOf(self.db.targets, Clean(name))
  if not index then return false end
  table.remove(self.db.targets, index)
  Changed(self)
  return true
end

-- The line for the tooltip of a mob called `name`, or nil if it isn't on the list.
function module:TooltipText(name)
  name = Clean(name)
  local targets = self.db.targets
  local index = name and IndexOf(targets, name)
  if not index then return nil end
  local _, used = self:MacroText()
  if index > used then return "Target Finder: on your list, but doesn't fit in the macro" end
  if #targets == 1 then return "Target Finder: the only mob you're finding" end
  return ("Target Finder: finding, %d of %d on your list"):format(index, #targets)
end

-- Whether `unit` is something to offer finding: it exists, has a name and isn't a player.
function module:CanFind(unit)
  if not UnitExists(unit) or not Clean(UnitName(unit)) then return false end
  local isPlayer = UnitIsPlayer(unit)
  return not IsSecret(isPlayer) and not isPlayer
end

-- Finds `unit` by name: instead of the current list, or with `add` as well as it.
-- Returns false if there's no such unit.
function module:UseUnit(unit, add)
  local name = UnitExists(unit) and Clean(UnitName(unit))
  if not name then return false end
  if add then self:Add(name) else self:SetTargets({ name }) end
  ns.Print("finding %s", table.concat(self.db.targets, ", "))
  return true
end

-- Finds whatever you're pointing at, or failing that your target.
function module:FindUnit()
  if not (self:UseUnit("mouseover") or self:UseUnit("target")) then
    ns.Print("hover over or target a mob first")
  end
end

---------------------------------------------------------------------------
-- Suggestions: mobs from your quests, then mobs you've seen
---------------------------------------------------------------------------

-- "Black Ooze slain: 3/10" or "3/10 Black Ooze slain" -> "Black Ooze" (English clients).
local function ObjectiveName(text)
  text = text:gsub("^%d+/%d+%s*", ""):gsub("%s*:%s*%d+/%d+$", "")
  text = text:gsub("%s+slain$", ""):gsub("%s+killed$", "")
  return Clean(text)
end

-- Mobs QuestieDB says quest `questID` needs: ones to kill, and ones that drop its items.
-- Each is { name = ..., item = the item it drops, if that's why it's here }.
local function DatabaseMobs(questID)
  local quests, npcs, items = QuestDB, NpcDB, ItemDB
  if not (type(quests) == "table" and quests.objectives and type(npcs) == "table" and npcs.name) then return {} end
  local mobs = {}
  local function add(npcID, item)
    local name = Clean(npcs.name(npcID))
    if name then table.insert(mobs, { name = name, item = item }) end
  end
  -- QuestieDB's objectives: [1] creatures, [3] items, [5] kill credits (several creatures count).
  local ok = pcall(function()
    local objectives = quests.objectives(questID) or {}
    for _, objective in ipairs(objectives[1] or {}) do add(objective[1]) end
    for _, objective in ipairs(objectives[5] or {}) do
      for _, npcID in ipairs(objective[1] or {}) do add(npcID) end
    end
    if type(items) == "table" and items.npcDrops then
      for _, objective in ipairs(objectives[3] or {}) do
        local item = items.name and Clean(items.name(objective[1])) or "an item"
        for _, npcID in ipairs(items.npcDrops(objective[1]) or {}) do add(npcID, item) end
      end
    end
  end)
  return ok and mobs or {}
end

-- Without QuestieDB: mob names read out of the unfinished kill objectives' text.
local function TextMobs(objectives)
  local mobs = {}
  for _, objective in ipairs(objectives) do
    local text = objective.text
    if objective.type == "monster" and not objective.finished and type(text) == "string"
      and not IsSecret(text) then
      local name = ObjectiveName(text)
      if name then table.insert(mobs, { name = name }) end
    end
  end
  return mobs
end

-- Your unfinished quests that have mobs to find, in quest log order:
-- { key = "quest123", title = ..., mobs = { { name = ..., item = ... }, ... } }.
local function QuestGroups()
  if questGroups then return questGroups end
  questGroups = {}
  local log = C_QuestLog
  if not (log and log.GetNumQuestLogEntries and log.GetInfo and log.GetQuestObjectives) then return questGroups end
  for i = 1, log.GetNumQuestLogEntries() do
    local info = log.GetInfo(i)
    if info and not info.isHeader and info.questID then
      local objectives = log.GetQuestObjectives(info.questID) or {}
      local unfinished = #objectives == 0
      for _, objective in ipairs(objectives) do
        if not objective.finished then unfinished = true end
      end
      local found = unfinished and DatabaseMobs(info.questID) or {}
      if unfinished and #found == 0 then found = TextMobs(objectives) end
      local mobs, have = {}, {}
      for _, mob in ipairs(found) do
        local lower = mob.name:lower()
        if not have[lower] then
          have[lower] = true
          table.insert(mobs, mob)
        end
      end
      table.sort(mobs, function(a, b) return a.name < b.name end)
      if #mobs > 0 then
        local title = type(info.title) == "string" and not IsSecret(info.title) and info.title or "Quest"
        table.insert(questGroups, { key = "quest" .. info.questID, title = title, mobs = mobs })
      end
    end
  end
  return questGroups
end

local function QuestNames()
  if questNames then return questNames end
  questNames = {}
  local have = {}
  for _, group in ipairs(QuestGroups()) do
    for _, mob in ipairs(group.mobs) do
      if not have[mob.name] then
        have[mob.name] = true
        table.insert(questNames, mob.name)
      end
    end
  end
  table.sort(questNames)
  return questNames
end

local function SeenNames(seen)
  local names = {}
  for name in pairs(seen) do table.insert(names, name) end
  table.sort(names, function(a, b)
    if seen[a] ~= seen[b] then return seen[a] > seen[b] end -- most recent first
    return a < b
  end)
  return names
end

function module:DatabaseState()
  return databaseState
end

-- Reads every NPC name out of QuestieDB, a batch per frame so the game doesn't stall.
-- Called when the window first opens, so players who never search don't pay for it.
function module:LoadDatabase()
  if databaseState ~= "idle" then return end
  local npcs = NpcDB
  local ok, ids
  if type(npcs) == "table" and npcs.GetAllIds and npcs.name then ok, ids = pcall(npcs.GetAllIds) end
  if not ok or type(ids) ~= "table" then
    databaseState = "missing"
    return
  end
  databaseState = "loading"
  local index = 1
  local function Step()
    local last = math.min(index + DATABASE_BATCH - 1, #ids)
    for i = index, last do
      local read, name = pcall(npcs.name, ids[i])
      if read and type(name) == "string" and name ~= "" then
        local lower = name:lower()
        if not databaseNames[lower] then
          databaseNames[lower] = name
          table.insert(databaseLower, lower)
        end
      end
    end
    index = last + 1
    if index <= #ids then
      C_Timer.After(0, Step)
      return
    end
    table.sort(databaseLower)
    databaseState = "ready"
    ns.Debug("loaded %d mob names from QuestieDB", #databaseLower)
    if self.UpdateUI then self.UpdateUI() end
  end
  Step()
end

-- Names containing `query`, ignoring case and skipping ones already on the list.
-- Returns up to `limit` of { name = ..., source = "quest" | "seen" | "database" }.
-- Database names only appear once you've typed something, names starting with it first.
function module:Search(query, limit)
  query = (query or ""):lower():match("^%s*(.-)%s*$")
  local results, used = {}, {}
  for _, name in ipairs(self.db.targets) do used[name:lower()] = true end
  local function consider(names, source)
    for _, name in ipairs(names) do
      if #results >= limit then return end
      local lower = name:lower()
      if not used[lower] and (query == "" or lower:find(query, 1, true)) then
        used[lower] = true
        table.insert(results, { name = name, source = source })
      end
    end
  end
  consider(QuestNames(), "quest")
  consider(SeenNames(self.db.seen), "seen")
  if query ~= "" and #results < limit then
    local starts, contains = {}, {}
    for _, lower in ipairs(databaseLower) do
      local at = not used[lower] and lower:find(query, 1, true)
      if at == 1 then
        table.insert(starts, databaseNames[lower])
        if #starts >= limit then break end
      elseif at and #contains < limit then
        table.insert(contains, databaseNames[lower])
      end
    end
    consider(starts, "database")
    consider(contains, "database")
  end
  return results
end

-- What the window lists under the search box, as rows to draw:
--   { kind = "header", key = ..., title = ..., names = { every mob in it }, open = bool }
--   { kind = "mob", name = ..., note = ..., listed = already on the find list }
-- With something typed that's the search results. With nothing typed it's a section per
-- quest and one for mobs seen recently; only sections in `expanded` list their mobs.
function module:Browse(query, expanded, limit)
  local entries = {}
  if (query or ""):match("%S") then
    for _, result in ipairs(self:Search(query, limit)) do
      table.insert(entries, { kind = "mob", name = result.name,
        note = result.source ~= "database" and result.source or nil })
    end
    return entries
  end
  local function section(key, title, mobs)
    local names = {}
    for i, mob in ipairs(mobs) do names[i] = mob.name end
    local open = expanded[key] and true or false
    table.insert(entries, { kind = "header", key = key, title = title, names = names, open = open })
    if not open then return end
    for _, mob in ipairs(mobs) do
      table.insert(entries, { kind = "mob", name = mob.name, note = mob.item,
        listed = IndexOf(self.db.targets, mob.name) ~= nil })
    end
  end
  for _, group in ipairs(QuestGroups()) do section(group.key, group.title, group.mobs) end
  local seen = {}
  for i, name in ipairs(SeenNames(self.db.seen)) do
    if i > SEEN_SHOWN then break end
    seen[i] = { name = name }
  end
  if #seen > 0 then section("seen", "Recently seen", seen) end
  return entries
end

-- `name` as the game spells it, if it's a mob we know.
function module:KnownName(name)
  local lower = name:lower()
  for _, known in ipairs(QuestNames()) do
    if known:lower() == lower then return known end
  end
  for known in pairs(self.db.seen) do
    if known:lower() == lower then return known end
  end
  return databaseNames[lower] or name
end

local function See(self, unit)
  local name = UnitName(unit)
  if type(name) ~= "string" or name == "" or IsSecret(name) then return end
  local isPlayer, isControlled = UnitIsPlayer(unit), UnitPlayerControlled(unit)
  if IsSecret(isPlayer) or IsSecret(isControlled) or isPlayer or isControlled then return end
  self.db.seen[name] = time()
end

---------------------------------------------------------------------------
-- Setup
---------------------------------------------------------------------------

module.events = {
  UPDATE_MOUSEOVER_UNIT = function(self) See(self, "mouseover") end,
  PLAYER_TARGET_CHANGED = function(self)
    See(self, "target")
    if self.UpdateUI then self.UpdateUI() end
  end,
  NAME_PLATE_UNIT_ADDED = function(self, unit) See(self, unit) end,
  QUEST_LOG_UPDATE = function(self)
    questGroups, questNames = nil, nil
    if self.UpdateUI then self.UpdateUI() end
  end,
  PLAYER_ENTERING_WORLD = function(self) self:Sync(false) end,
  PLAYER_REGEN_ENABLED = function(self)
    if self.dirty then self:Sync(false) end
    if self.UpdateUI then self.UpdateUI() end
  end,
}

function module:OnInit()
  -- Forget the mobs seen longest ago.
  local names = SeenNames(self.db.seen)
  for i = SEEN_LIMIT + 1, #names do self.db.seen[names[i]] = nil end
  if self.InitUI then self.InitUI() end
end

function module:OnEnable()
  if IsLoggedIn() then self:Sync(false) end
  if self.UpdateUI then self.UpdateUI() end
end

function module:OnDisable()
  if self.UpdateUI then self.UpdateUI() end
end

-- Key binding (Bindings.xml): find the mob under the cursor.
function ForeverUtils_FindHover()
  if module.active then module:FindUnit() end
end

BINDING_HEADER_FOREVERUTILS = "ForeverUtils"
BINDING_NAME_FOREVERUTILS_FIND_HOVER = "Find the mob under the cursor"
_G["BINDING_NAME_CLICK ForeverUtilsFinderButton:LeftButton"] = "Target a mob on the find list"

SLASH_FOREVERUTILSFINDER1 = "/tf"
SLASH_FOREVERUTILSFINDER2 = "/tfind"

SlashCmdList.FOREVERUTILSFINDER = function(input)
  if not module.active then
    ns.Print("Target Finder is off - turn it on with /fu finder on")
    return
  end
  input = (input or ""):match("^%s*(.-)%s*$")
  local cmd, arg = input:match("^(%S*)%s*(.-)$")
  cmd = cmd:lower()
  if input == "" then
    if module.ToggleWindow then module.ToggleWindow() end
  elseif input:lower() == "clear" then
    module:SetTargets({})
    ns.Print("find list cleared")
  elseif input:lower() == "list" then
    local _, used = module:MacroText()
    local targets = module.db.targets
    ns.Print("finding: %s", #targets > 0 and table.concat(targets, ", ") or "nothing")
    if used < #targets then ns.Print("only the first %d fit in the macro", used) end
  elseif input:lower() == "hover" then
    module:FindUnit()
  elseif (cmd == "+" or cmd == "add") and arg ~= "" then
    module:Add(arg)
    ns.Print("finding: %s", table.concat(module.db.targets, ", "))
  elseif (cmd == "-" or cmd == "remove") and arg ~= "" then
    if not module:Remove(arg) then ns.Print("%s isn't on the find list", arg) end
  elseif cmd == "help" or cmd == "?" then
    ns.Print("/tf - window | <name> | + <name> | - <name> | hover | list | clear")
  else
    module:SetTargets({ input })
    ns.Print("finding %s", table.concat(module.db.targets, ", "))
  end
end
