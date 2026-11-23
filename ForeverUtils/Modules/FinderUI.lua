local _, ns = ...

-- Target Finder's window (search and the find list) and its floating button.

local module = ns.finder
local MAX_TARGETS = 5
local LIST_ROWS = 10
local SEARCH_LIMIT = 40
local ROW_HEIGHT = 20
local WIDTH = 280

local MARKERS = {
  { key = 0, name = "No marker" },
  { key = 1, name = "Star" },
  { key = 2, name = "Circle" },
  { key = 3, name = "Diamond" },
  { key = 4, name = "Triangle" },
  { key = 5, name = "Moon" },
  { key = 6, name = "Square" },
  { key = 7, name = "Cross" },
  { key = 8, name = "Skull" },
}

local function Label(parent, text, template)
  local fs = parent:CreateFontString(nil, "ARTWORK", template or "GameFontHighlight")
  fs:SetText(text)
  fs:SetJustifyH("LEFT")
  return fs
end

---------------------------------------------------------------------------
-- Window
---------------------------------------------------------------------------

local window = CreateFrame("Frame", "ForeverUtilsFinderWindow", UIParent, "BasicFrameTemplateWithInset")
window:SetSize(WIDTH, 566)
window:SetPoint("CENTER")
window:SetMovable(true)
window:SetClampedToScreen(true)
window:EnableMouse(true)
window:RegisterForDrag("LeftButton")
window:Hide()

Label(window, "Target Finder", "GameFontNormal"):SetPoint("TOP", 0, -5)
Label(window, "Type a mob's name and press Enter", "GameFontDisableSmall"):SetPoint("TOPLEFT", 16, -32)

local search = CreateFrame("EditBox", nil, window, "InputBoxTemplate")
search:SetSize(WIDTH - 40, 20)
search:SetPoint("TOPLEFT", 22, -46)
search:SetAutoFocus(false)

Label(window, "Finding", "GameFontNormal"):SetPoint("TOPLEFT", 16, -76)
local emptyNote = Label(window, "Nothing yet.", "GameFontDisable")
emptyNote:SetPoint("TOPLEFT", 16, -96)

local targetRows = {}
for i = 1, MAX_TARGETS do
  local row = CreateFrame("Frame", nil, window)
  row:SetSize(WIDTH - 32, ROW_HEIGHT)
  row:SetPoint("TOPLEFT", 16, -94 - (i - 1) * ROW_HEIGHT)
  row.text = Label(row, "")
  row.text:SetPoint("LEFT")
  row.text:SetPoint("RIGHT", -80, 0) -- room for the arrows, the magnifying glass and the remove button
  row.text:SetWordWrap(false)
  -- Up and down: where the mob comes in the order the macro tries them.
  row.arrows = {}
  for index, arrow in ipairs({ { "Up", -1, -62 }, { "Down", 1, -46 } }) do
    local move = CreateFrame("Button", nil, row)
    move:SetSize(16, 16)
    move:SetPoint("RIGHT", arrow[3], 0)
    move:SetNormalTexture("Interface\\Buttons\\Arrow-" .. arrow[1] .. "-Up")
    move:SetPushedTexture("Interface\\Buttons\\Arrow-" .. arrow[1] .. "-Down")
    move:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight", "ADD")
    move:SetScript("OnClick", function() module:Move(row.name, arrow[2]) end)
    move:SetScript("OnEnter", function(self)
      GameTooltip:SetOwner(self, "ANCHOR_TOP")
      GameTooltip:AddLine(arrow[2] < 0 and "Try this mob sooner" or "Try this mob later")
      GameTooltip:Show()
    end)
    move:SetScript("OnLeave", function() GameTooltip:Hide() end)
    row.arrows[index] = move
  end
  local remove = CreateFrame("Button", nil, row, "UIPanelCloseButton")
  remove:SetSize(22, 22)
  remove:SetPoint("RIGHT")
  remove:SetScript("OnClick", function() module:Remove(row.name) end)
  targetRows[i] = row
end

-- A magnifying glass beside each mob that targets just that one. Targeting needs a secure
-- button, and a window holding secure buttons couldn't be opened, closed or dragged in
-- combat. So these belong to the screen, not the window: they're laid over the rows, and
-- put away for the length of a fight.
local findButtons = {}
for i = 1, MAX_TARGETS do
  local find = CreateFrame("Button", "ForeverUtilsFinderRowButton" .. i, UIParent, "SecureActionButtonTemplate")
  find:SetSize(ROW_HEIGHT, ROW_HEIGHT)
  find:SetFrameStrata("DIALOG")
  find:RegisterForClicks("AnyUp", "AnyDown")
  -- Runs a macro of its own, written for this mob as the click lands.
  find:SetAttribute("type1", "macro")
  find:SetAttribute("macro", module.SOLO_MACRO_NAME)
  find:SetScript("PreClick", function(self) module:Solo(self.name) end)
  local icon = find:CreateTexture(nil, "ARTWORK")
  icon:SetSize(14, 14)
  icon:SetPoint("CENTER")
  icon:SetTexture("Interface\\Common\\UI-Searchbox-Icon")
  find:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight", "ADD")
  find:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_TOP")
    GameTooltip:AddLine("Target " .. (self.name or "this mob"))
    GameTooltip:AddLine("Targets only this one, whatever else is on your list.", 1, 1, 1, true)
    GameTooltip:Show()
  end)
  find:SetScript("OnLeave", function() GameTooltip:Hide() end)
  find:Hide()
  findButtons[i] = find
end

-- Lays the magnifying glasses over their rows, or hides them. Secure buttons can't be
-- touched in combat, so this does nothing then; they come back when the fight ends.
local function PlaceFindButtons(hide)
  if InCombatLockdown() then return end
  for i, find in ipairs(findButtons) do
    local row = targetRows[i]
    local name = not hide and window:IsShown() and row.name
    local right, top = row:GetRight(), row:GetTop()
    if name and right and top then
      find.name = name
      find:ClearAllPoints()
      find:SetPoint("TOPRIGHT", UIParent, "BOTTOMLEFT", right - 24, top)
      find:Show()
    else
      find:Hide()
    end
  end
end

function module.OnCombat()
  PlaceFindButtons(true)
  if module.HideMenu then module.HideMenu() end
end

window:SetScript("OnDragStart", function(self)
  PlaceFindButtons(true)
  self:StartMoving()
end)
window:SetScript("OnDragStop", function(self)
  self:StopMovingOrSizing()
  PlaceFindButtons()
end)
window:SetScript("OnHide", function() PlaceFindButtons(true) end)

local overflowNote = Label(window, "", "GameFontDisableSmall")
overflowNote:SetPoint("TOPLEFT", 16, -96 - MAX_TARGETS * ROW_HEIGHT)

-- The list under the find list: your quests and recently seen mobs as sections that
-- open and close, or the search results while something is typed. Scrolls with the wheel.
local listTop = -116 - MAX_TARGETS * ROW_HEIGHT
local listTitle = Label(window, "", "GameFontNormal")
listTitle:SetPoint("TOPLEFT", 16, listTop)
local listHint = Label(window, "", "GameFontDisableSmall") -- on its own line under the title
listHint:SetPoint("TOPLEFT", 16, listTop - 16)
listHint:SetWidth(WIDTH - 32)
listHint:SetWordWrap(false)

local list = CreateFrame("Frame", nil, window)
list:SetSize(WIDTH - 32, LIST_ROWS * ROW_HEIGHT)
list:SetPoint("TOPLEFT", 16, listTop - 32)
list:EnableMouseWheel(true)

local entries, offset = {}, 0
local RefreshList

local listRows = {}
for i = 1, LIST_ROWS do
  local row = CreateFrame("Button", nil, list)
  row:SetSize(WIDTH - 32, ROW_HEIGHT)
  row:SetPoint("TOPLEFT", 0, -(i - 1) * ROW_HEIGHT)
  row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
  row.note = Label(row, "", "GameFontDisableSmall")
  row.note:SetPoint("RIGHT", -2, 0)
  row.text = Label(row, "")
  row.text:SetWordWrap(false)
  row:SetScript("OnClick", function()
    local entry = row.entry
    if entry.kind == "header" then
      if IsShiftKeyDown() and #entry.names > 0 then
        module:SetTargets(entry.names)
      else
        module.db.expanded[entry.key] = not entry.open
        RefreshList()
      end
    elseif IsShiftKeyDown() then
      module:Add(entry.name)
    elseif entry.service then
      module:FindNearest(entry.service) -- also says how far and which way
    else
      module:SetTargets({ entry.name })
      search:SetText("")
      search:ClearFocus()
    end
  end)
  -- Says what a click and a shift-click do, since one replaces the list and the other adds.
  function row.ShowTip()
    local entry = row.entry
    if not entry then return end
    GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
    if entry.kind == "header" then
      GameTooltip:AddLine(entry.title)
      GameTooltip:AddLine("Click: " .. (entry.open and "close" or "open"), 1, 1, 1)
      if #entry.names > 0 then
        GameTooltip:AddLine("Shift-click: find all of its mobs, replacing your list", 1, 1, 1)
      end
    else
      GameTooltip:AddLine(entry.label or entry.name)
      if entry.listed then GameTooltip:AddLine("Already on your find list.", 0.6, 0.6, 0.6) end
      GameTooltip:AddLine(entry.service and "Click: find the nearest one, replacing your list"
        or "Click: find only this mob, replacing your list", 1, 1, 1)
      GameTooltip:AddLine("Shift-click: add it to your list", 1, 1, 1)
    end
    GameTooltip:Show()
  end
  row:SetScript("OnEnter", row.ShowTip)
  row:SetScript("OnLeave", function() GameTooltip:Hide() end)
  listRows[i] = row
end

local moreNote = Label(window, "", "GameFontDisableSmall")
moreNote:SetPoint("TOPLEFT", list, "BOTTOMLEFT", 0, -2)
local listEmpty = Label(window, "", "GameFontDisable")
listEmpty:SetPoint("TOPLEFT", list, "TOPLEFT", 0, -2)
listEmpty:SetWidth(WIDTH - 32)

function RefreshList()
  local query = search:GetText()
  local searching = query:match("%S") ~= nil
  entries = module:Browse(query, module.db.expanded, SEARCH_LIMIT)
  offset = math.max(0, math.min(offset, #entries - LIST_ROWS))
  for i, row in ipairs(listRows) do
    local entry = entries[i + offset]
    row.entry = entry
    row:SetShown(entry ~= nil)
    if entry then
      local header = entry.kind == "header"
      row.text:ClearAllPoints()
      row.text:SetPoint("LEFT", (header and 2 or 14) + (entry.level or 0) * 12, 0)
      row.text:SetPoint("RIGHT", row.note, "LEFT", -4, 0)
      if header then
        row.text:SetText(("|cffffd100%s %s|r"):format(entry.open and "-" or "+", entry.title))
        row.note:SetText(entry.count)
      else
        local text = entry.label or entry.name
        row.text:SetText(entry.listed and "|cff888888" .. text .. "|r" or text)
        row.note:SetText(entry.listed and "finding" or entry.note or "")
      end
    end
    -- The row under the cursor may now hold something else (scrolled, opened, clicked).
    if GameTooltip:IsOwned(row) then
      if entry then row.ShowTip() else GameTooltip:Hide() end
    end
  end
  local below = #entries - offset - LIST_ROWS
  moreNote:SetText(below > 0 and ("%d more - scroll down"):format(below) or "")
  listTitle:SetText(searching and "Search results" or "Pick from")
  listHint:SetText(searching and "Click to find, shift-click to add."
    or "Click a mob. Shift-click a quest: all its mobs.") -- search results have no level

  local state = module:DatabaseState()
  local hint = "No known mob matches. Enter uses the name anyway."
  if state == "loading" then
    hint = "Loading mob names..."
  elseif not searching then
    hint = "Your quests' mobs, and mobs you see, appear here."
  elseif state == "missing" then
    hint = "No mob you've seen matches. Enter uses the name anyway.\n\nInstall the QuestieDB addon to search every mob."
  end
  listEmpty:SetText(#entries == 0 and hint or "")
end

list:SetScript("OnMouseWheel", function(_, delta)
  offset = offset - delta * 3
  RefreshList()
end)

local allowDead = CreateFrame("CheckButton", nil, window, "UICheckButtonTemplate")
allowDead:SetSize(24, 24)
allowDead:SetPoint("BOTTOMLEFT", 12, 34)
Label(allowDead, "Include dead mobs"):SetPoint("LEFT", allowDead, "RIGHT", 2, 1)
allowDead:SetScript("OnClick", function(self)
  module.db.allowDead = self:GetChecked() and true or false
  module:Changed()
end)

-- The raid marker the macro puts on the mob it finds: one icon each, the chosen one lit.
Label(window, "Mark with"):SetPoint("BOTTOMLEFT", 16, 66)
local markerButtons = {}
for i = 0, 8 do
  local pick = CreateFrame("Button", nil, window)
  pick:SetSize(18, 18)
  pick:SetPoint("BOTTOMLEFT", 80 + (i == 0 and 0 or 6 + i * 18), 63)
  if i == 0 then
    pick.text = Label(pick, "-", "GameFontHighlightLarge") -- no marker
    pick.text:SetPoint("CENTER")
  else
    pick.icon = pick:CreateTexture(nil, "ARTWORK")
    pick.icon:SetAllPoints()
    pick.icon:SetTexture("Interface\\TargetingFrame\\UI-RaidTargetingIcon_" .. i)
  end
  pick:SetScript("OnClick", function()
    module.db.marker = i
    module:Changed()
  end)
  pick:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_TOP")
    GameTooltip:AddLine(MARKERS[i + 1].name)
    GameTooltip:Show()
  end)
  pick:SetScript("OnLeave", function() GameTooltip:Hide() end)
  markerButtons[i] = pick
end

local macroButton = CreateFrame("Button", nil, window, "UIPanelButtonTemplate")
macroButton:SetSize(110, 22)
macroButton:SetPoint("BOTTOMLEFT", 14, 10)
macroButton:SetText("Pick up macro")
macroButton:SetScript("OnClick", function()
  if InCombatLockdown() then
    ns.Print("can't pick up the macro in combat")
    return
  end
  module:Sync(true)
  PickupMacro(module.MACRO_NAME)
end)
macroButton:SetScript("OnEnter", function(self)
  GameTooltip:SetOwner(self, "ANCHOR_TOP")
  GameTooltip:AddLine(module.MACRO_NAME .. " macro")
  GameTooltip:AddLine("Click, then drop it on an action bar. It always targets the mobs listed here.", 1, 1, 1, true)
  GameTooltip:Show()
end)
macroButton:SetScript("OnLeave", function() GameTooltip:Hide() end)

local clearButton = CreateFrame("Button", nil, window, "UIPanelButtonTemplate")
clearButton:SetSize(70, 22)
clearButton:SetPoint("BOTTOMRIGHT", -14, 10)
clearButton:SetText("Clear")
clearButton:SetScript("OnClick", function() module:SetTargets({}) end)

local function RefreshWindow()
  local db = module.db
  local _, used = module:MacroText()
  for i, row in ipairs(targetRows) do
    local name = db.targets[i]
    row.name = name
    row:SetShown(name ~= nil)
    if name then
      row.text:SetText(i > used and "|cff888888" .. name .. "|r" or name)
      -- Dimmed where there's nowhere to move to.
      row.arrows[1]:SetAlpha(i > 1 and 1 or 0.25)
      row.arrows[2]:SetAlpha(i < #db.targets and 1 or 0.25)
    end
  end
  emptyNote:SetShown(#db.targets == 0)
  overflowNote:SetText(used < #db.targets
    and ("Only the first %d fit in the macro."):format(used) or "")

  PlaceFindButtons()
  RefreshList()
  allowDead:SetChecked(db.allowDead)
  for i, pick in pairs(markerButtons) do pick:SetAlpha(i == db.marker and 1 or 0.3) end
end

window:SetScript("OnShow", function()
  module:LoadDatabase()
  RefreshWindow()
  -- The rows have no position until the window has been drawn once.
  C_Timer.After(0, function() PlaceFindButtons() end)
end)
search:SetScript("OnTextChanged", function()
  offset = 0
  RefreshWindow()
end)
search:SetScript("OnEscapePressed", search.ClearFocus)
search:SetScript("OnEnterPressed", function(self)
  local text = self:GetText()
  if text:match("%S") then
    if IsShiftKeyDown() then module:Add(text) else module:SetTargets({ text }) end
  end
  self:SetText("")
  self:ClearFocus()
end)

function module.ToggleWindow()
  window:SetShown(not window:IsShown())
end

---------------------------------------------------------------------------
-- Floating button: runs the macro, so it must be a secure button, and secure
-- buttons can't be shown, hidden or moved in combat.
---------------------------------------------------------------------------

local button = CreateFrame("Button", "ForeverUtilsFinderButton", UIParent,
  "SecureActionButtonTemplate,UIPanelButtonTemplate")
button:SetSize(150, 24)
button:SetPoint("CENTER", 0, -160)
button:SetMovable(true)
button:SetClampedToScreen(true)
button:RegisterForDrag("LeftButton")
-- Both, so it works whichever way "cast on key down" is set.
button:RegisterForClicks("AnyUp", "AnyDown")
button:SetAttribute("type1", "macro")
button:SetAttribute("macro", module.MACRO_NAME)
-- Not an action the game knows, so a shift-click targets nothing and PostClick opens the menu.
button:SetAttribute("shift-type1", "helper")
button:Hide()

-- The shift-click menu: find the nearest vendor, trainer and so on, and target it in the
-- same click. Only a secure button can target, so this is a panel of them and not one of
-- the game's menus. Each one finds its service as the click lands (which rewrites the
-- macro) and then runs the macro.
local MENU_ROW, MENU_COLUMN = 18, 124
local helperMenu = CreateFrame("Frame", "ForeverUtilsFinderMenu", UIParent)
helperMenu:SetFrameStrata("DIALOG")
helperMenu:SetClampedToScreen(true)
helperMenu:Hide()
local menuBack = helperMenu:CreateTexture(nil, "BACKGROUND")
menuBack:SetAllPoints()
menuBack:SetColorTexture(0, 0, 0, 0.9)

-- Behind the menu, covering the screen: a click anywhere else closes it.
local menuCatcher = CreateFrame("Button", nil, UIParent)
menuCatcher:SetAllPoints()
menuCatcher:SetFrameStrata("HIGH")
menuCatcher:RegisterForClicks("AnyUp")
menuCatcher:Hide()

local function HideHelperMenu()
  menuCatcher:Hide()
  if not InCombatLockdown() then helperMenu:Hide() end -- it holds secure buttons
end
menuCatcher:SetScript("OnClick", HideHelperMenu)

do
  local counts = { [false] = 0, [true] = 0 } -- rows so far in each column
  for _, column in ipairs({ { false, "Find the nearest" }, { true, "Profession trainer" } }) do
    local title = Label(helperMenu, column[2], "GameFontNormalSmall")
    title:SetPoint("TOPLEFT", 8 + (column[1] and MENU_COLUMN or 0), -8)
  end
  for _, service in ipairs(module.SERVICES) do
    local row = counts[service.profession] + 1
    counts[service.profession] = row
    local pick = CreateFrame("Button", nil, helperMenu, "SecureActionButtonTemplate")
    pick:SetSize(MENU_COLUMN - 8, MENU_ROW)
    pick:SetPoint("TOPLEFT", 6 + (service.profession and MENU_COLUMN or 0), -8 - row * MENU_ROW)
    pick:RegisterForClicks("AnyUp", "AnyDown")
    pick:SetAttribute("type1", "macro")
    pick:SetAttribute("macro", module.MACRO_NAME)
    pick:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
    Label(pick, service.name):SetPoint("LEFT", 4, 0)
    -- On the way down, so the macro is ready whichever half of the click the game acts on.
    pick:SetScript("PreClick", function(_, _, down)
      if down then module:FindNearest(service.key) end
    end)
    pick:SetScript("PostClick", function(_, _, down)
      if not down then HideHelperMenu() end
    end)
  end
  helperMenu:SetSize(MENU_COLUMN * 2 + 8, 16 + (math.max(counts[false], counts[true]) + 1) * MENU_ROW)
end

-- In combat the panel can't be shown, so there it's one of the game's menus: it finds
-- the service but can't target it for you.
local function ShowPlainMenu(owner)
  if not (MenuUtil and MenuUtil.CreateContextMenu) then
    module.ToggleWindow()
    return
  end
  MenuUtil.CreateContextMenu(owner, function(_, root)
    root:CreateTitle("Find the nearest")
    local professions -- a submenu, made when the first profession comes up
    for _, service in ipairs(module.SERVICES) do
      local function find() module:FindNearest(service.key) end
      if service.profession then
        professions = professions or root:CreateButton("Profession trainer")
        professions:CreateButton(service.name, find)
      else
        root:CreateButton(service.name, find)
      end
    end
  end)
end

module.HideMenu = HideHelperMenu

local function ShowHelperMenu(owner)
  if InCombatLockdown() then
    ShowPlainMenu(owner)
    return
  end
  if helperMenu:IsShown() then
    HideHelperMenu()
    return
  end
  module:LoadDatabase() -- so the NPC list is ready by the time you pick
  helperMenu:ClearAllPoints()
  helperMenu:SetPoint("BOTTOMLEFT", owner, "TOPLEFT", 0, 4)
  menuCatcher:Show()
  helperMenu:Show()
end

button:SetScript("PostClick", function(self, mouseButton, down)
  if down then return end
  if mouseButton == "RightButton" then
    module.ToggleWindow()
  elseif mouseButton == "LeftButton" and IsShiftKeyDown() then
    ShowHelperMenu(self)
  elseif mouseButton == "LeftButton" and #module.db.targets == 0
    and (GetMacroIndexByName(module.MACRO_NAME) or 0) == 0 then
    -- Nothing to find and no macro yet. (An existing macro opens the window itself.)
    module.ToggleWindow()
  end
end)
button:SetScript("OnDragStart", function(self)
  if IsShiftKeyDown() and not InCombatLockdown() then self:StartMoving() end
end)
button:SetScript("OnDragStop", function(self)
  self:StopMovingOrSizing()
  local point, _, relativePoint, x, y = self:GetPoint()
  module.db.buttonPoint = { point, relativePoint, x, y }
end)
button:SetScript("OnEnter", function(self)
  GameTooltip:SetOwner(self, "ANCHOR_TOP")
  GameTooltip:AddLine("Target Finder")
  local targets = module.db.targets
  for _, name in ipairs(targets) do GameTooltip:AddLine(name, 1, 1, 1) end
  if #targets == 0 then GameTooltip:AddLine("Nothing to find yet.", 1, 1, 1) end
  GameTooltip:AddLine(#targets > 0 and "Click: target  Right-click: edit" or "Click: pick a mob", 0.6, 0.6, 0.6)
  GameTooltip:AddLine("Shift-click: nearest vendor, trainer...  Shift-drag: move", 0.6, 0.6, 0.6)
  GameTooltip:Show()
end)
button:SetScript("OnLeave", function() GameTooltip:Hide() end)

---------------------------------------------------------------------------
-- Target frame: a Find button on it, and entries in its right-click menu.
---------------------------------------------------------------------------

local targetButton
if TargetFrame then
  -- A child of the target frame, so it comes and goes with it, and disappears if a
  -- unit frame addon hides Blizzard's.
  targetButton = CreateFrame("Button", "ForeverUtilsFinderTargetButton", TargetFrame, "UIPanelButtonTemplate")
  targetButton:SetSize(64, 20)
  targetButton:SetPoint("BOTTOMLEFT", TargetFrame, "TOPLEFT", 24, -14)
  targetButton:Hide()
  targetButton:SetScript("OnClick", function() module:UseUnit("target", IsShiftKeyDown()) end)
  targetButton:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_TOP")
    GameTooltip:AddLine("Target Finder")
    GameTooltip:AddLine("Click: find only this mob", 1, 1, 1)
    GameTooltip:AddLine("Shift-click: add it to your find list", 1, 1, 1)
    GameTooltip:Show()
  end)
  targetButton:SetScript("OnLeave", function() GameTooltip:Hide() end)
end

local function UpdateTargetButton()
  if not targetButton then return end
  local show = module.active and module.db.targetButton and module:CanFind("target")
  targetButton:SetShown(show)
  if show then
    local onList = module:TooltipText(UnitName("target")) ~= nil
    targetButton:SetText(onList and "Finding" or "Find")
    targetButton:SetEnabled(not onList)
  end
end

if Menu and Menu.ModifyMenu then
  Menu.ModifyMenu("MENU_UNIT_TARGET", function(_, root)
    ns.Safe("finder target menu", function()
      if not (module.active and module.db.targetMenu and module:CanFind("target")) then return end
      root:CreateDivider()
      root:CreateTitle("ForeverUtils")
      root:CreateButton("Find this mob", function() module:UseUnit("target") end)
      root:CreateButton("Add to find list", function() module:UseUnit("target", true) end)
    end)
  end)
end

---------------------------------------------------------------------------
-- Mob tooltips: a line on mobs that are on the find list. Only ever adds a line,
-- so it sits alongside whatever other addons add.
---------------------------------------------------------------------------

local function AddTooltipLine(tooltip)
  if tooltip ~= GameTooltip or not module.active or not module.db.tooltip then return end
  local text = module:TooltipText(UnitName("mouseover"))
  if text then tooltip:AddLine(text, 0.2, 0.8, 1) end
end

-- Other addons share this hook, and in instances the game withholds unit names. Whatever
-- goes wrong here is skipped, never raised into the tooltip.
local function OnUnitTooltip(tooltip)
  ns.Safe("finder tooltip", AddTooltipLine, tooltip)
end

if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and Enum and Enum.TooltipDataType then
  TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Unit, OnUnitTooltip)
else
  GameTooltip:HookScript("OnTooltipSetUnit", OnUnitTooltip) -- older clients
end

---------------------------------------------------------------------------
-- Minimap pins: where the mobs on the find list are known to spawn, drawn with the raid
-- marker the macro uses. Addons can't see where a mob actually is.
---------------------------------------------------------------------------

local MAX_PINS = 30
local PIN_INTERVAL = 0.1 -- seconds between redraws
-- Yards from the centre of the minimap to its edge at each zoom level, outdoors.
local ZOOM_YARDS = { [0] = 233.3, 200, 166.7, 133.3, 100, 66.7 }

local pinFrame = CreateFrame("Frame", nil, Minimap)
pinFrame:SetAllPoints()
pinFrame:SetFrameLevel(Minimap:GetFrameLevel() + 5)
pinFrame:Hide()
local pins = {}

local function UpdatePins()
  local view = ns.Plain(C_Minimap and C_Minimap.GetViewRadius and C_Minimap.GetViewRadius())
  if type(view) ~= "number" or view <= 0 then view = ZOOM_YARDS[Minimap:GetZoom()] or ZOOM_YARDS[0] end
  local facing = GetCVar("rotateMinimap") == "1" and ns.Plain(GetPlayerFacing()) or nil
  if type(facing) ~= "number" then facing = nil end
  local radius = Minimap:GetWidth() / 2 - 4
  local marker = module.db.marker
  local found = module:MinimapPins(view, facing, MAX_PINS)
  for i, pin in ipairs(found) do
    local texture = pins[i] or pinFrame:CreateTexture(nil, "OVERLAY")
    pins[i] = texture
    if marker > 0 then
      texture:SetTexture("Interface\\TargetingFrame\\UI-RaidTargetingIcon_" .. marker)
      texture:SetVertexColor(1, 1, 1)
      texture:SetSize(pin.edge and 12 or 14, pin.edge and 12 or 14)
    else
      texture:SetColorTexture(1, 0.82, 0) -- no marker chosen: a gold dot
      texture:SetSize(5, 5)
    end
    texture:SetAlpha(pin.edge and 0.7 or 1)
    texture:ClearAllPoints()
    texture:SetPoint("CENTER", Minimap, "CENTER", pin.x * radius, pin.y * radius)
    texture:Show()
  end
  for i = #found + 1, #pins do pins[i]:Hide() end
end

local sinceUpdate = 0
pinFrame:SetScript("OnUpdate", function(_, elapsed)
  sinceUpdate = sinceUpdate + elapsed
  if sinceUpdate < PIN_INTERVAL then return end
  sinceUpdate = 0
  ns.Safe("finder minimap pins", UpdatePins)
end)

function module.InitUI()
  local saved = module.db.buttonPoint
  if type(saved) == "table" and saved[1] then
    button:ClearAllPoints()
    button:SetPoint(saved[1], UIParent, saved[2], saved[3], saved[4])
  end
end

local function UpdateUI()
  local db = module.db
  local targets = db.targets
  if targets[1] then
    button:SetText(#targets > 1 and ("%s +%d"):format(targets[1], #targets - 1) or targets[1])
  else
    button:SetText("Target Finder")
  end
  -- Left for PLAYER_REGEN_ENABLED, which calls this again, when in combat.
  if not InCombatLockdown() then
    button:SetShown(module.active and db.showButton and (db.keepButton or #targets > 0))
  end
  UpdateTargetButton()
  pinFrame:SetShown(module.active and db.minimapPins and #targets > 0)
  if not module.active then window:Hide() end
  if window:IsShown() then RefreshWindow() end
end

-- Called from events, including in combat and in instances: an error is noted, not raised.
function module.UpdateUI()
  ns.Safe("finder window", UpdateUI)
end

function module:BuildOptions(UI, anchor)
  local show = UI.Checkbox("Show the floating target button",
    "Click targets, right-click opens the list, shift-click finds a service, shift-drag moves it.",
    self.db, "showButton", anchor, nil, { onChange = module.UpdateUI })
  local keep = UI.Checkbox("Keep the button when there's nothing to find", nil,
    self.db, "keepButton", show, nil, { onChange = module.UpdateUI })
  local tooltip = UI.Checkbox("Show on mob tooltips",
    "Hovering a mob on your find list says so, and whether it's the only one.",
    self.db, "tooltip", keep)
  local targetButtonBox = UI.Checkbox("Show a Find button on the target frame", nil,
    self.db, "targetButton", tooltip, nil, { onChange = module.UpdateUI })
  local targetMenu = UI.Checkbox("Add Find to the target's right-click menu", nil,
    self.db, "targetMenu", targetButtonBox)
  local minimapPins = UI.Checkbox("Show spawn points on the minimap",
    "Where your mobs are known to spawn, drawn with the marker below. Needs QuestieDB.",
    self.db, "minimapPins", targetMenu, nil, { onChange = module.UpdateUI })
  local marker, dropdown = UI.Dropdown("Mark the mob with", self.db, "marker", MARKERS, minimapPins, nil, 120,
    function() module:Changed() end)
  local open = UI.Button("Open Target Finder", 150, function()
    if module.active then
      if not window:IsShown() then module.ToggleWindow() end
    else
      ns.Print("Target Finder is off - tick Enable Target Finder first")
    end
  end)
  open:SetPoint("LEFT", dropdown, "RIGHT", 16, 0)
  return marker
end
