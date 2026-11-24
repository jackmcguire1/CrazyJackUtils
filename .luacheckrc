std = "lua51"
max_line_length = 120
exclude_files = { ".luarocks", ".cache", ".venv" }
files["spec"] = { std = "+busted" }

ignore = {
  "212/self", -- unused self in widget scripts and module callbacks
}

globals = {
  "BINDING_HEADER_CRAZYJACKUTILS",
  "BINDING_NAME_CRAZYJACKUTILS_FIND_HOVER",
  "CrazyJackUtils_FindHover",
  "CrazyJackUtils_OnAddonCompartmentClick",
  "SLASH_CRAZYJACKUTILSFINDER1",
  "SLASH_CRAZYJACKUTILSFINDER2",
  "CrazyJackUtilsDB",
  "SLASH_CRAZYJACKUTILS1",
  "SLASH_CRAZYJACKUTILS2",
  "SLASH_CRAZYJACKUTILS3",
  "SlashCmdList",
}

read_globals = {
  -- WoW API
  "C_Map",
  "C_Minimap",
  "CreateVector2D",
  "GetCVar",
  "GetPlayerFacing",
  "LibQuestieDB",
  "MenuUtil",
  "UnitClass",
  "UnitFactionGroup",
  "UnitIsTapDenied",
  "SetRaidTarget",
  "GetRaidTargetIndex",
  "UnitPosition",
  "ToggleWorldMap",
  "C_Texture",
  "hooksecurefunc",
  "WorldMapFrame",
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
