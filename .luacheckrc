-- luacheck configuration for SakaMind (WoW Forever, Lua 5.1).
-- Run from the repo root:
--   & "$env:LOCALAPPDATA\Programs\luacheck\luacheck.exe" SakaMindProbe

std = "lua51"
max_line_length = false
codes = true

-- Globals the add-ons define: saved variables and slash commands.
globals = {
  "SakaMindProbeDB",
  "SLASH_SAKAMINDPROBE1",
  "SlashCmdList",
}

-- WoW API and FrameXML globals the add-ons read.
read_globals = {
  -- Lua extensions in the WoW client
  "date",
  "format",
  "strsplit",
  "strtrim",
  "wipe",

  -- Secret values
  "issecretvalue",

  -- Frames and widgets
  "CreateFrame",
  "PlaySoundFile",
  "STANDARD_TEXT_FONT",
  "UIParent",

  -- Client, account and settings
  "GetBuildInfo",
  "GetCVar",
  "GetNormalizedRealmName",
  "GetRealmName",
  "GetTime",
  "InCombatLockdown",
  "IsTrialAccount",
  "IsVeteranTrialAccount",
  "SetCVar",

  -- Group and units
  "IsInGroup",
  "IsInRaid",
  "LE_PARTY_CATEGORY_INSTANCE",
  "UnitClass",
  "UnitExists",
  "UnitFullName",
  "UnitGUID",
  "UnitName",

  -- Battle.net
  "BNGetNumFriends",

  -- Namespaces, utilities and enums
  "AnchorUtil",
  "AuraContainerSortMethod",
  "C_AddOns",
  "C_BattleNet",
  "C_ChatInfo",
  "C_ClickBindings",
  "C_CurveUtil",
  "C_DamageMeter",
  "C_Secrets",
  "C_Spell",
  "C_Timer",
  "C_UnitAuras",
  "Enum",
}
