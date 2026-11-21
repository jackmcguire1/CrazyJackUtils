local _, ns = ...

-- Target Finder's window (search and the find list) and its floating button.

local module = ns.finder
local MAX_TARGETS = 5
local LIST_ROWS = 10
local SEARCH_LIMIT = 40
local ROW_HEIGHT = 20
local WIDTH = 260

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
window:SetSize(WIDTH, 540)
window:SetPoint("CENTER")
window:SetMovable(true)
window:SetClampedToScreen(true)
window:EnableMouse(true)
window:RegisterForDrag("LeftButton")
window:SetScript("OnDragStart", window.StartMoving)
window:SetScript("OnDragStop", window.StopMovingOrSizing)
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
  row.text:SetPoint("RIGHT", -24, 0)
  local remove = CreateFrame("Button", nil, row, "UIPanelCloseButton")
  remove:SetSize(22, 22)
  remove:SetPoint("RIGHT")
  remove:SetScript("OnClick", function() module:Remove(row.name) end)
  targetRows[i] = row
end

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
        module.db.expanded[entry.key] = not entry.open or nil
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
      row.text:SetPoint("LEFT", header and 2 or 14, 0)
      row.text:SetPoint("RIGHT", row.note, "LEFT", -4, 0)
      if header then
        row.text:SetText(("|cffffd100%s %s|r"):format(entry.open and "-" or "+", entry.title))
        row.note:SetText(entry.count or #entry.names)
      else
        local text = entry.label or entry.name
        row.text:SetText(entry.listed and "|cff888888" .. text .. "|r" or text)
        row.note:SetText(entry.listed and "finding" or entry.note or "")
      end
    end
  end
  local below = #entries - offset - LIST_ROWS
  moreNote:SetText(below > 0 and ("%d more - scroll down"):format(below) or "")
  listTitle:SetText(searching and "Search results" or "Pick from")
  listHint:SetText(searching and "Click to find, shift-click to add."
    or "Shift-click a quest to find all its mobs.")

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
    if name then row.text:SetText(i > used and "|cff888888" .. name .. "|r" or name) end
  end
  emptyNote:SetShown(#db.targets == 0)
  overflowNote:SetText(used < #db.targets
    and ("Only the first %d fit in the macro."):format(used) or "")

  RefreshList()
  allowDead:SetChecked(db.allowDead)
end

window:SetScript("OnShow", function()
  module:LoadDatabase()
  RefreshWindow()
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

-- The shift-click menu: find the nearest vendor, trainer and so on.
local function ShowHelperMenu(owner)
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
    if not (module.active and module.db.targetMenu and module:CanFind("target")) then return end
    root:CreateDivider()
    root:CreateTitle("ForeverUtils")
    root:CreateButton("Find this mob", function() module:UseUnit("target") end)
    root:CreateButton("Add to find list", function() module:UseUnit("target", true) end)
  end)
end

---------------------------------------------------------------------------
-- Mob tooltips: a line on mobs that are on the find list. Only ever adds a line,
-- so it sits alongside whatever other addons add.
---------------------------------------------------------------------------

local function OnUnitTooltip(tooltip)
  if tooltip ~= GameTooltip or not module.active or not module.db.tooltip then return end
  local text = module:TooltipText(UnitName("mouseover"))
  if text then tooltip:AddLine(text, 0.2, 0.8, 1) end
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
  local view = C_Minimap and C_Minimap.GetViewRadius and C_Minimap.GetViewRadius()
  if type(view) ~= "number" or view <= 0 then view = ZOOM_YARDS[Minimap:GetZoom()] or ZOOM_YARDS[0] end
  local facing = GetCVar("rotateMinimap") == "1" and GetPlayerFacing() or nil
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
  UpdatePins()
end)

function module.InitUI()
  local saved = module.db.buttonPoint
  if type(saved) == "table" and saved[1] then
    button:ClearAllPoints()
    button:SetPoint(saved[1], UIParent, saved[2], saved[3], saved[4])
  end
end

function module.UpdateUI()
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
  return (UI.Dropdown("Mark the mob with", self.db, "marker", MARKERS, minimapPins, nil, 120,
    function() module:Changed() end))
end
