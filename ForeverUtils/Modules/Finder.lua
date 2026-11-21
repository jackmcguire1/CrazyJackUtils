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
    keepButton = true, -- keep it on screen while there's nothing to find
    tooltip = true,    -- say so on the tooltip of a mob that's on the list
    targetButton = true, -- the Find button on the target frame
    targetMenu = true,   -- the entries in the target's right-click menu
    expanded = {},       -- [section key] = true for sections left open in the window
    minimapPins = true,  -- show the mobs' known spawn points on the minimap
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
local databaseIds = {}       -- [lowercased name] = NPC id, or a list of ids sharing the name
local servicePoints = {}     -- where vendors, trainers and the like stand: { c, n, w, service }
local targetPoints           -- where the mobs on the find list spawn; nil when the list changed
local areaMaps               -- [QuestieDB area id] = UiMapID; false if QuestieDB has no such table
local pendingNearest         -- service asked for while the NPC list was still loading

-- Classic's NPC flags, used if QuestieDB doesn't publish its own.
local FLAGS = {
  VENDOR = 4, FLIGHT_MASTER = 8, TRAINER = 16, INNKEEPER = 128, BANKER = 256,
  AUCTIONEER = 4096, STABLEMASTER = 8192, REPAIR = 16384,
}

-- The services Target Finder can find the nearest of. `class`: only your class's trainer.
-- `words`: the trainer's title must contain one of them (English clients).
local SERVICES = {
  { key = "vendor", name = "Vendor", flag = "VENDOR" },
  { key = "repair", name = "Repair", flag = "REPAIR" },
  { key = "banker", name = "Banker", flag = "BANKER" },
  { key = "innkeeper", name = "Innkeeper", flag = "INNKEEPER" },
  { key = "flight", name = "Flight master", flag = "FLIGHT_MASTER" },
  { key = "auctioneer", name = "Auctioneer", flag = "AUCTIONEER" },
  { key = "stable", name = "Stable master", flag = "STABLEMASTER" },
  { key = "class", name = "Class trainer", flag = "TRAINER", class = true },
  { key = "alchemy", name = "Alchemy", flag = "TRAINER", words = { "alchem" } },
  { key = "blacksmithing", name = "Blacksmithing", flag = "TRAINER", words = { "blacksmith" } },
  { key = "cooking", name = "Cooking", flag = "TRAINER", words = { "cook" } },
  { key = "enchanting", name = "Enchanting", flag = "TRAINER", words = { "enchant" } },
  { key = "engineering", name = "Engineering", flag = "TRAINER", words = { "engineer" } },
  { key = "firstaid", name = "First Aid", flag = "TRAINER", words = { "first aid", "physician", "surgeon" } },
  { key = "fishing", name = "Fishing", flag = "TRAINER", words = { "fish" } },
  { key = "herbalism", name = "Herbalism", flag = "TRAINER", words = { "herbalis" } },
  { key = "leatherworking", name = "Leatherworking", flag = "TRAINER", words = { "leatherwork" } },
  { key = "mining", name = "Mining", flag = "TRAINER", words = { "mining", "miner" } },
  { key = "skinning", name = "Skinning", flag = "TRAINER", words = { "skinn" } },
  { key = "tailoring", name = "Tailoring", flag = "TRAINER", words = { "tailor" } },
}
for _, service in ipairs(SERVICES) do service.profession = service.words ~= nil end
module.SERVICES = SERVICES

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
  targetPoints = nil
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

---------------------------------------------------------------------------
-- Where NPCs are: QuestieDB's spawn points, as world positions in yards
---------------------------------------------------------------------------

-- A QuestieDB field of NPC `id`, or nil if it has none or this QuestieDB lacks the field.
local function Field(npcs, field, id)
  local read = npcs[field]
  if type(read) ~= "function" then return nil end
  local ok, value = pcall(read, id)
  return ok and value or nil
end

-- QuestieDB keys spawn points by area id; the game's map functions want UiMapIDs.
local function AreaMaps()
  if areaMaps ~= nil then return areaMaps end
  areaMaps = false
  local ok, zones = pcall(function() return LibQuestieDB.Support.Get("ZoneDB").private end)
  if not ok or type(zones) ~= "table" then return areaMaps end
  local maps = {}
  -- Both are Lua source for a table. The second corrects the first.
  for _, field in ipairs({ "areaIdToUiMapId", "areaIdToUiMapIdOverride" }) do
    local chunk = type(zones[field]) == "string" and loadstring(zones[field])
    local read, rows = pcall(chunk or error)
    if read and type(rows) == "table" then
      for area, map in pairs(rows) do maps[area] = map end
    end
  end
  if next(maps) then areaMaps = maps end
  return areaMaps
end

-- Every spawn point of NPC `id` as { c = continent, n = yards north, w = yards west }.
local function SpawnPoints(npcs, id)
  local points = {}
  local maps, api = AreaMaps(), C_Map
  local spawns = Field(npcs, "spawns", id)
  if not maps or type(spawns) ~= "table" or not (api and api.GetWorldPosFromMapPos) then return points end
  for area, coords in pairs(spawns) do
    local map = maps[area]
    if type(map) == "number" and map > 0 and type(coords) == "table" then
      for _, coord in ipairs(coords) do
        local x, y = coord[1], coord[2]
        if type(x) == "number" and type(y) == "number" and x >= 0 and y >= 0 then -- -1: in an instance
          local at = CreateVector2D and CreateVector2D(x / 100, y / 100) or { x = x / 100, y = y / 100 }
          local ok, continent, pos = pcall(api.GetWorldPosFromMapPos, map, at)
          if ok and type(pos) == "table" and type(pos.x) == "number" and type(pos.y) == "number" then
            table.insert(points, { c = continent, n = pos.x, w = pos.y })
          end
        end
      end
    end
  end
  return points
end

-- Where you are, in the same terms: yards north, yards west, continent. nil where the
-- game won't say, such as inside instances.
function module:PlayerPosition()
  if not UnitPosition then return nil end
  local n, w, _, continent = UnitPosition("player")
  if IsSecret(n) or IsSecret(w) or type(n) ~= "number" or type(w) ~= "number" then return nil end
  return n, w, continent
end

local function HasFlag(flags, flag)
  return math.floor(flags / flag) % 2 == 1
end

local function FlagValue(name)
  local lib = LibQuestieDB
  local published = type(lib) == "table" and type(lib.Enum) == "table"
    and type(lib.Enum.npcFlags) == "table" and lib.Enum.npcFlags[name]
  return type(published) == "number" and published or FLAGS[name]
end

-- The keys of the services an NPC with these flags and this title ("Warrior Trainer") offers.
local function ServiceKeys(flags, title, class)
  local keys = {}
  title = title and title:lower() or ""
  for _, service in ipairs(SERVICES) do
    local offers = HasFlag(flags, FlagValue(service.flag))
    if offers and service.class then
      offers = class ~= nil and title == class .. " trainer"
    elseif offers and service.words then
      offers = false
      for _, word in ipairs(service.words) do
        if title:find(word, 1, true) then offers = true end
      end
    end
    if offers then table.insert(keys, service.key) end
  end
  return keys
end

-- Notes where NPC `id` stands if it offers a service to your faction.
local function ReadService(npcs, id, name, faction, class)
  local flags = Field(npcs, "npcFlags", id)
  if type(flags) ~= "number" or flags < 4 then return end -- below 4: just gossip and quests
  local title = Field(npcs, "subName", id)
  title = type(title) == "string" and title ~= "" and title or nil
  local keys = ServiceKeys(flags, title, class)
  if #keys == 0 then return end
  local friendly = Field(npcs, "friendlyToFaction", id)
  if faction and type(friendly) == "string" and not friendly:find(faction, 1, true) then return end
  local service = { name = name, title = title, keys = keys }
  for _, point in ipairs(SpawnPoints(npcs, id)) do
    point.service = service
    table.insert(servicePoints, point)
  end
end

local COMPASS = { "east", "north-east", "north", "north-west", "west", "south-west", "south", "south-east" }

local function Direction(east, north)
  return COMPASS[math.floor(math.atan2(north, east) / (math.pi / 4) + 0.5) % 8 + 1]
end

-- The nearest NPC offering each service on your continent:
-- [service key] = { name = ..., title = ..., distance = yards, direction = "north-east" }.
-- nil if the game won't say where you are.
function module:NearestServices()
  local n, w, continent = self:PlayerPosition()
  if not n then return nil end
  local best, bestPoint = {}, {}
  for _, point in ipairs(servicePoints) do
    if point.c == continent then
      local distance = (point.n - n) ^ 2 + (point.w - w) ^ 2
      for _, key in ipairs(point.service.keys) do
        if not best[key] or distance < best[key] then best[key], bestPoint[key] = distance, point end
      end
    end
  end
  local found = {}
  for key, point in pairs(bestPoint) do
    found[key] = { name = point.service.name, title = point.service.title,
      distance = math.sqrt(best[key]), direction = Direction(w - point.w, point.n - n) }
  end
  return found
end

local function ServiceNamed(text)
  text = text:lower()
  for _, service in ipairs(SERVICES) do
    if service.key == text or service.name:lower() == text then return service end
  end
end

-- Finds the nearest NPC offering service `key`, replacing the find list.
function module:FindNearest(key)
  local service = ServiceNamed(key)
  if not service then return end
  self:LoadDatabase()
  if databaseState == "loading" then
    pendingNearest = service.key
    ns.Print("reading QuestieDB's NPC list - one moment")
    return
  end
  if databaseState == "missing" or not AreaMaps() then
    ns.Print("finding the nearest %s needs the QuestieDB addon", service.name:lower())
    return
  end
  local found = self:NearestServices()
  local hit = found and found[service.key]
  if not found then
    ns.Print("the game doesn't say where you are in here, so the nearest one can't be worked out")
  elseif not hit then
    ns.Print("QuestieDB doesn't know a %s on this continent", service.name:lower())
  else
    self:SetTargets({ hit.name })
    ns.Print("nearest %s: %s%s, %d yards %s", service.name:lower(), hit.name,
      hit.title and (" <" .. hit.title .. ">") or "", hit.distance + 0.5, hit.direction)
  end
end

-- Where the mobs on the find list are known to spawn.
local function TargetPoints(self)
  if targetPoints then return targetPoints end
  if databaseState ~= "ready" then return {} end
  targetPoints = {}
  for _, name in ipairs(self.db.targets) do
    local ids = databaseIds[name:lower()]
    if type(ids) == "number" then ids = { ids } end
    for _, id in ipairs(ids or {}) do
      for _, point in ipairs(SpawnPoints(NpcDB, id)) do table.insert(targetPoints, point) end
    end
  end
  return targetPoints
end

-- Pins for the minimap: the find list's spawn points within `radius` yards of you, nearest
-- first, at most `limit`. Each is { x = ..., y = ... } in minimap radii right of and above
-- its centre. If none are that close, the nearest one, pushed out to the rim, with
-- edge = true. `facing`: your facing in radians if the minimap rotates with you.
function module:MinimapPins(radius, facing, limit)
  local pins = {}
  self:LoadDatabase()
  local n, w, continent = self:PlayerPosition()
  if not n then return pins end
  local nearest
  for _, point in ipairs(TargetPoints(self)) do
    if point.c == continent then
      local east, south = w - point.w, n - point.n
      local pin = { x = east / radius, y = -south / radius, distance = math.sqrt(east ^ 2 + south ^ 2) }
      if facing then
        local sin, cos = math.sin(facing), math.cos(facing)
        pin.x, pin.y = (east * cos - south * sin) / radius, -(south * cos + east * sin) / radius
      end
      if pin.distance <= radius then table.insert(pins, pin) end
      if not nearest or pin.distance < nearest.distance then nearest = pin end
    end
  end
  if #pins == 0 and nearest then
    nearest.x, nearest.y = nearest.x * radius / nearest.distance, nearest.y * radius / nearest.distance
    nearest.edge = true
    return { nearest }
  end
  table.sort(pins, function(a, b) return a.distance < b.distance end)
  for i = #pins, limit + 1, -1 do pins[i] = nil end
  return pins
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
  local side = UnitFactionGroup and UnitFactionGroup("player")
  local faction = side == "Alliance" and "A" or side == "Horde" and "H" or nil
  local className = UnitClass and UnitClass("player")
  local class = type(className) == "string" and className:lower() or nil
  local function Step()
    local last = math.min(index + DATABASE_BATCH - 1, #ids)
    for i = index, last do
      local read, name = pcall(npcs.name, ids[i])
      if read and type(name) == "string" and name ~= "" then
        local lower = name:lower()
        local known = databaseIds[lower]
        if not known then
          databaseNames[lower] = name
          table.insert(databaseLower, lower)
          databaseIds[lower] = ids[i]
        elseif type(known) == "number" then
          databaseIds[lower] = { known, ids[i] }
        else
          table.insert(known, ids[i])
        end
        ReadService(npcs, ids[i], name, faction, class)
      end
    end
    index = last + 1
    if index <= #ids then
      C_Timer.After(0, Step)
      return
    end
    table.sort(databaseLower)
    databaseState = "ready"
    targetPoints = nil
    ns.Debug("loaded %d mob names and %d service locations from QuestieDB", #databaseLower, #servicePoints)
    if pendingNearest then
      local key = pendingNearest
      pendingNearest = nil
      self:FindNearest(key)
    end
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
-- quest, one for mobs seen recently and, with QuestieDB, two for the nearest services
-- and profession trainers; only sections in `expanded` list their rows. A service's row
-- also has label = "Repair: <name>" to show and service = its key. Service headers have
-- names = {}: there's no finding them all at once.
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

  local nearest = databaseState == "ready" and self:NearestServices() or {}
  local function services(key, title, profession)
    local rows = {}
    for _, service in ipairs(SERVICES) do
      local hit = service.profession == profession and nearest[service.key]
      if hit then
        table.insert(rows, { kind = "mob", name = hit.name, service = service.key,
          label = service.name .. ": " .. hit.name, note = ("%d yd"):format(hit.distance + 0.5),
          listed = IndexOf(self.db.targets, hit.name) ~= nil })
      end
    end
    if #rows == 0 then return end
    local open = expanded[key] and true or false
    table.insert(entries, { kind = "header", key = key, title = title, names = {}, count = #rows, open = open })
    for _, row in ipairs(open and rows or {}) do table.insert(entries, row) end
  end
  services("services", "Nearest services", false)
  services("professions", "Nearest profession trainers", true)
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
  elseif cmd == "nearest" and ServiceNamed(arg) then
    module:FindNearest(arg)
  elseif cmd == "nearest" then
    local names = {}
    for i, service in ipairs(SERVICES) do names[i] = service.key end
    ns.Print("/tf nearest <one of: %s>", table.concat(names, ", "))
  elseif cmd == "help" or cmd == "?" then
    ns.Print("/tf - window | <name> | + <name> | - <name> | hover | list | clear | nearest <service>")
  else
    module:SetTargets({ input })
    ns.Print("finding %s", table.concat(module.db.targets, ", "))
  end
end
