local _, ns = ...

local panel = CreateFrame("Frame")
panel.name = "ForeverUtils"
local refreshers = {}

-- Extra space a widget needs below it (a checkbox's note, a dropdown taller than its label).
local gaps = setmetatable({}, { __mode = "k" })

-- Widgets for the options panel. Modules use these from BuildOptions. Each one is placed
-- under `anchor` and returns the widget to anchor the next one to.
local UI = {}
ns.UI = UI
UI.panel = panel

function UI.Below(widget, anchor, offsetY)
  widget:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, (offsetY or -6) - (gaps[anchor] or 0))
  return widget
end

-- Called when the panel is shown, to load settings into a custom widget.
function UI.OnRefresh(fn)
  table.insert(refreshers, fn)
end

function UI.Label(text, template, anchor, offsetY)
  local fs = panel:CreateFontString(nil, "ARTWORK", template or "GameFontHighlight")
  fs:SetText(text)
  fs:SetJustifyH("LEFT")
  if anchor then UI.Below(fs, anchor, offsetY) end
  return fs
end

-- A checkbox for settings[key]. opts.inverted: checked means the setting is false.
-- opts.onChange: called after a click.
function UI.Checkbox(label, note, settings, key, anchor, offsetY, opts)
  opts = opts or {}
  local cb = CreateFrame("CheckButton", nil, panel, "UICheckButtonTemplate")
  cb:SetSize(26, 26)
  UI.Below(cb, anchor, offsetY)
  local text = UI.Label(label)
  text:SetPoint("LEFT", cb, "RIGHT", 4, 1)
  if note then
    local sub = UI.Label(note, "GameFontDisable")
    sub:SetPoint("TOPLEFT", text, "BOTTOMLEFT", 0, -2)
    gaps[cb] = 12
  end
  cb:SetScript("OnClick", function(self)
    settings[key] = (self:GetChecked() and true or false) ~= (opts.inverted or false)
    if opts.onChange then opts.onChange() end
  end)
  UI.OnRefresh(function() cb:SetChecked(settings[key] ~= (opts.inverted or false)) end)
  return cb
end

function UI.Button(text, width, onClick)
  local b = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
  b:SetSize(width, 22)
  b:SetText(text)
  b:SetScript("OnClick", onClick)
  return b
end

-- A labelled dropdown that stores the picked choice's key in settings[key].
-- choices: list of { key = ..., name = ... }. Uses Blizzard's menu dropdown, as Questie
-- does on Forever. Returns the label (to anchor below) and the dropdown (to anchor beside).
function UI.Dropdown(label, settings, key, choices, anchor, offsetY, width, onChange)
  local title = UI.Label(label, nil, anchor, offsetY or -14)
  title:SetWidth(100)
  gaps[title] = 8

  local dropdown = CreateFrame("DropdownButton", nil, panel, "WowStyle1DropdownTemplate")
  dropdown:SetPoint("LEFT", title, "RIGHT", 8, 0)
  dropdown:SetWidth(width or 160)
  dropdown:SetupMenu(function(_, root)
    for _, choice in ipairs(choices) do
      root:CreateRadio(choice.name,
        function() return settings[key] == choice.key end,
        function()
          settings[key] = choice.key
          if onChange then onChange() end
        end)
    end
  end)
  -- Regenerating updates the text showing the picked choice.
  UI.OnRefresh(function() dropdown:GenerateMenu() end)
  return title, dropdown
end

local function Build()
  local title = UI.Label("ForeverUtils", "GameFontNormalLarge")
  title:SetPoint("TOPLEFT", 16, -16)
  local sub = UI.Label("A collection of small utilities. Turn each one on or off below.", nil, title)

  local enabled = UI.Checkbox("Enable ForeverUtils", "Turns every module off when unchecked.",
    ns.db, "enabled", sub, -12, { onChange = ns.Refresh })
  local minimap = UI.Checkbox("Show minimap button", nil, ns.db, "minimapHide", enabled, nil,
    { inverted = true, onChange = ns.UpdateMinimapButton })

  ---@type any -- a label, then whichever widget each module ends on
  local last = UI.Label("Modules", "GameFontNormal", minimap, -20)
  if #ns.modules == 0 then
    UI.Label("No modules installed yet.", "GameFontDisable", last, -8)
  end
  for _, module in ipairs(ns.modules) do
    last = UI.Checkbox(module.name, module.description, module.db, "enabled", last, -8,
      { onChange = ns.Refresh })
    if module.BuildOptions then last = module:BuildOptions(UI, last) or last end
  end
end

panel:SetScript("OnShow", function()
  for _, refresh in ipairs(refreshers) do refresh() end
end)

function ns.InitOptions()
  Build()
  if Settings and Settings.RegisterCanvasLayoutCategory then
    local category = Settings.RegisterCanvasLayoutCategory(panel, panel.name)
    Settings.RegisterAddOnCategory(category)
    ns.OpenOptions = function() Settings.OpenToCategory(category:GetID()) end
  elseif InterfaceOptions_AddCategory then
    InterfaceOptions_AddCategory(panel)
    ns.OpenOptions = function()
      -- Called twice: the first call sometimes only opens the frame.
      InterfaceOptionsFrame_OpenToCategory(panel)
      InterfaceOptionsFrame_OpenToCategory(panel)
    end
  end
end
