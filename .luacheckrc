std = "lua51"
max_line_length = 120
exclude_files = { ".luarocks", ".cache", ".venv" }
files["spec"] = { std = "+busted" }

ignore = {
  "212/self", -- unused self in widget scripts and module callbacks
}

globals = {
  "BINDING_HEADER_FOREVERUTILS",
  "BINDING_NAME_FOREVERUTILS_FIND_HOVER",
  "ForeverUtils_FindHover",
  "ForeverUtils_OnAddonCompartmentClick",
  "SLASH_FOREVERUTILSFINDER1",
  "SLASH_FOREVERUTILSFINDER2",
  "ForeverUtilsDB",
  "SLASH_FOREVERUTILS1",
  "SLASH_FOREVERUTILS2",
  "SlashCmdList",
}

read_globals = {
  -- WoW API
  "C_QuestLog",
  "C_Timer",
  "CreateFrame",
  "CreateMacro",
  "Enum",
  "EditMacro",
  "GetMacroIndexByName",
  "InCombatLockdown",
  "IsLoggedIn",
  "IsShiftKeyDown",
  "issecretvalue",
  "PickupMacro",
  "time",
  "TargetFrame",
  "TooltipDataProcessor",
  "UIParent",
  "UnitExists",
  "UnitIsPlayer",
  "UnitName",
  "UnitPlayerControlled",
  "GameTooltip",
  "GetCursorPosition",
  "Menu",
  "Minimap",
  -- Other addons
  "ItemDB", -- QuestieDB
  "NpcDB",
  "QuestDB",
  -- FrameXML
  "InterfaceOptions_AddCategory",
  "InterfaceOptionsFrame_OpenToCategory",
  "Settings",
}
