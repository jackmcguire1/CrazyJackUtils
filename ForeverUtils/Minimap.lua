local _, ns = ...

-- A plain minimap button. The name contains "MinimapButton" so minimap button
-- collectors such as MinimapButtonButton pick it up.
local ICON = "Interface\\Icons\\INV_Misc_Wrench_01"

local button

local function UpdatePosition()
  local angle = math.rad(ns.db.minimapAngle)
  local radius = Minimap:GetWidth() / 2 + 10
  button:ClearAllPoints()
  button:SetPoint("CENTER", Minimap, "CENTER", math.cos(angle) * radius, math.sin(angle) * radius)
end

local function OnDragUpdate()
  local mx, my = Minimap:GetCenter()
  local px, py = GetCursorPosition()
  local scale = Minimap:GetEffectiveScale()
  ns.db.minimapAngle = math.deg(math.atan2(py / scale - my, px / scale - mx))
  UpdatePosition()
end

local function OnClick(_, mouseButton)
  if mouseButton == "RightButton" then
    ns.SetEnabled(not ns.db.enabled)
  elseif ns.OpenOptions then
    ns.OpenOptions()
  end
end

local function OnEnter(self)
  GameTooltip:SetOwner(self, "ANCHOR_LEFT")
  GameTooltip:AddLine("ForeverUtils")
  GameTooltip:AddLine(ns.db.enabled and "|cff00ff00On|r" or "|cffff4040Off|r")
  GameTooltip:AddLine("Left-click: options", 1, 1, 1)
  GameTooltip:AddLine("Right-click: turn on or off", 1, 1, 1)
  GameTooltip:Show()
end

function ns.UpdateMinimapButton()
  if not button then return end
  button:SetShown(not ns.db.minimapHide)
end

function ns.InitMinimap()
  button = CreateFrame("Button", "ForeverUtils_MinimapButton", Minimap)
  button:SetSize(31, 31)
  button:SetFrameStrata("MEDIUM")
  button:SetFrameLevel(8)
  button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  button:RegisterForDrag("LeftButton")
  button:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")

  local background = button:CreateTexture(nil, "BACKGROUND")
  background:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
  background:SetSize(20, 20)
  background:SetPoint("TOPLEFT", 7, -5)

  local icon = button:CreateTexture(nil, "ARTWORK")
  icon:SetTexture(ICON)
  icon:SetSize(17, 17)
  icon:SetPoint("TOPLEFT", 7, -6)
  icon:SetTexCoord(0.05, 0.95, 0.05, 0.95)

  local border = button:CreateTexture(nil, "OVERLAY")
  border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
  border:SetSize(53, 53)
  border:SetPoint("TOPLEFT")

  button:SetScript("OnClick", OnClick)
  button:SetScript("OnEnter", OnEnter)
  button:SetScript("OnLeave", function() GameTooltip:Hide() end)
  button:SetScript("OnDragStart", function(self)
    -- Once a collector has taken the button, leave positioning to it.
    if self:GetParent() == Minimap then self:SetScript("OnUpdate", OnDragUpdate) end
  end)
  button:SetScript("OnDragStop", function(self) self:SetScript("OnUpdate", nil) end)

  UpdatePosition()
  ns.UpdateMinimapButton()
end

-- Entry in the minimap's addon compartment dropdown (## AddonCompartmentFunc in the TOC).
function ForeverUtils_OnAddonCompartmentClick(_, mouseButton)
  OnClick(nil, mouseButton)
end
