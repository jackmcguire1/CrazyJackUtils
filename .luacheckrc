std = "lua51"
max_line_length = 120
exclude_files = { ".luarocks", ".cache", ".venv" }
files["spec"] = { std = "+busted" }

ignore = {
  "212/self", -- unused self in widget scripts and module callbacks
}

globals = {
  "ForeverUtils_OnAddonCompartmentClick",
  "ForeverUtilsDB",
  "SLASH_FOREVERUTILS1",
  "SLASH_FOREVERUTILS2",
  "SlashCmdList",
}

read_globals = {
  -- WoW API
  "CreateFrame",
  "GameTooltip",
  "GetCursorPosition",
  "Minimap",
  -- FrameXML
  "InterfaceOptions_AddCategory",
  "InterfaceOptionsFrame_OpenToCategory",
  "Settings",
}
