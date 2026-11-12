-- SakaMindProbe: a throwaway test add-on for SakaMind, for WoW Forever.
--
-- During a real dungeon run it finds out which ways of sharing defensive
-- cooldowns between party members work, above all during boss fights:
--
--   1. Add-on messages (party and whisper) and Battle.net game data. The
--      probe sends test messages by itself: on trash pulls, every few
--      seconds during a boss fight, when the chat lock starts and ends, and
--      after the boss. It records what each send returned and what the
--      other player's probe received. Probes find each other with a short
--      "hello" on the group channel; the automatic tests run only when
--      another probe user is in the group, and go only to them. After each
--      boss, each probe sends its own results to the others, so one
--      player's log holds every side.
--   2. Whether your own casts arrive with a readable spell ID in combat
--      (the paladin's Lay on Hands, for example).
--   3. Whether Blizzard's damage meter shows a party member's Lay on Hands
--      (or Tranquility) during the fight.
--   4. Party members' defensive buffs, and Forbearance, on the probe's
--      panel during the fight, and a "ding" when a defensive lands.
--   5. Which of these spells the game never hides.
--   6. Whether party members' casts reach add-ons in combat and during a
--      boss with a hidden spell ID, and whether the calls a display would
--      need accept that hidden ID. Nothing is shown; it runs in any group.
--   7. /smp flags: Blizzard's yes/no flags for every spell, to see whether
--      some combination of them singles out Lay on Hands.
--
-- Everything goes to SakaMindProbeDB.log (the flags to
-- SakaMindProbeDB.flags), which the game writes to
-- WTF\Account\<account>\SavedVariables\SakaMindProbe.lua on /reload or
-- logout. Type /smp for the commands.
--
-- Rule kept throughout: a value that may be secret is never compared or
-- calculated with. It is checked with issecretvalue first, or only passed
-- on to widgets.

local ADDON_NAME = ...

local PREFIX = "SakaMindProbe"
local PROTOCOL = "2"
local LOG_MAX = 1500
local SEND_EVERY = 8 -- seconds between automatic sends during a boss fight
local METER_EVERY = 3 -- seconds between damage meter checks in combat
local DING = 567458 -- the game's "Ding" sound file; DBM uses it on this client
local FONT = STANDARD_TEXT_FONT
local ICON = 20
local METER_ICONS = 6
local PARTY_UNITS = { "party1", "party2", "party3", "party4" }

-- Spells ------------------------------------------------------------------

-- Spell IDs on Forever 1.60.1 (wago.tools SpellName, build 70862). Every
-- rank and version is listed; extra IDs do no harm in a filter.
local LAY_ON_HANDS = { name = "Lay on Hands", ids = { 633, 2800, 10310, 9257, 17233 } }
local TRANQUILITY = { name = "Tranquility", ids = { 740, 8918, 9862, 9863 }, sound = true }
local FORBEARANCE = { name = "Forbearance", ids = { 25771 } }

-- Buffs a defensive puts on a friendly unit (shown on the panel). "sound"
-- registers a ding for all its IDs (true) or for the IDs listed.
local DEFENSIVES = {
  { name = "Divine Shield", ids = { 642, 1020 }, sound = true },
  { name = "Divine Protection", ids = { 498, 5573 }, sound = true },
  { name = "Blessing of Protection", ids = { 1022, 5599, 10278 }, sound = true },
  { name = "Blessing of Sacrifice", ids = { 6940, 20729 } },
  { name = "Divine Intervention", ids = { 19753 } },
  { name = "Barkskin", ids = { 22812, 20655, 428713, 1289128 }, sound = { 22812 } },
  { name = "Innervate", ids = { 29166 }, sound = true },
  TRANQUILITY,
  { name = "Frenzied Regeneration", ids = { 22842, 428708 } },
  { name = "Nature's Swiftness", ids = { 17116, 16188 } },
  { name = "Power Infusion", ids = { 10060 } },
  { name = "Pain Suppression", ids = { 402004 } },
  { name = "Fear Ward", ids = { 6346 } },
  { name = "Shield Wall", ids = { 871 } },
  { name = "Last Stand", ids = { 12976 } },
  { name = "Evasion", ids = { 5277 } },
  { name = "Ice Block", ids = { 11958, 27619 } },
  { name = "Deterrence", ids = { 19263 } },
}

-- Casts that leave no buff on a friend, or a buff with another spell ID.
local OTHER_CASTS = {
  LAY_ON_HANDS,
  { name = "Divine Intervention (cast)", ids = { 19752 } },
  { name = "Rebirth", ids = { 20484, 20739, 20742, 20747, 20748 } },
  { name = "Last Stand (cast)", ids = { 12975 } },
}

-- spell ID -> spell name, for every spell in the lists.
local function NameSet(...)
  local set = {}
  for i = 1, select("#", ...) do
    for _, spell in ipairs((select(i, ...))) do
      for _, id in ipairs(spell.ids) do
        set[id] = spell.name
      end
    end
  end
  return set
end

-- spell ID -> true, the form aura containers take.
local function TrueSet(list)
  local set = {}
  for _, spell in ipairs(list) do
    for _, id in ipairs(spell.ids) do
      set[id] = true
    end
  end
  return set
end

local WATCHED_CASTS = NameSet(DEFENSIVES, OTHER_CASTS)
local METER_SPELLS = NameSet({ LAY_ON_HANDS, TRANQUILITY })
local LAY_ON_HANDS_IDS = TrueSet({ LAY_ON_HANDS })

-- State -------------------------------------------------------------------

local db
local pending = {} -- log lines from before the saved variables load
local encounter -- { name, start } while a boss fight is on
local seq = 0
local partyNames = {} -- unit -> "Name-Realm", read out of combat
local partyGUIDs = {} -- unit -> GUID, read out of combat
local links = {} -- party member's GUID -> Battle.net game account ID
-- Players running the probe, by GUID: { guid, name, lastSeen }. Players are
-- told apart by GUID, which every message carries, because names differ:
-- on Forever the game calls a player "Name Realm-INTERNALREALM" in messages
-- but "Name" and "Realm" in unit names. "name" is the one from messages,
-- which also serves as the whisper target.
local peers = {}
local helloAnswered = {} -- GUID -> when their last hello was answered
local myGUID
local stats = {} -- phase -> { sent = { channel -> { result -> count } }, recv = { channel -> count } }
local ownCasts = {} -- phase -> { readable, hidden }
local meterStatus = {} -- unit -> last damage meter status line
local meterSeen = {} -- "unit:spellID" -> true once reported this fight
local alerted = {} -- channel -> true once a boss-time arrival was announced
local bossReadable = {} -- watched spells you cast with a readable spell ID during the current boss
local meterFinds = {} -- Lay on Hands or Tranquility found on the damage meter since the boss started
local lastBoss -- this probe's results for the last boss, kept for sending
local resultsState -- nil, "waiting" (not due yet) or "due" (waiting for the chat lock to end)
local soundIDs = {}
local errorsShown = 0
local panel
local rows = {}
local refreshAfterCombat = false
local encounterTicker, meterTicker

-- Helpers -----------------------------------------------------------------

local function IsSecret(value)
  return issecretvalue ~= nil and issecretvalue(value) == true
end

-- A printable form of a value that may be secret.
local function Show(value)
  if IsSecret(value) then
    return "<secret>"
  end
  return tostring(value)
end

-- Cuts text to at most max bytes without splitting a UTF-8 character.
local function Cut(text, max)
  if #text <= max then
    return text
  end
  local cut = max
  while cut > 0 do
    local byte = text:byte(cut + 1)
    if byte < 0x80 or byte >= 0xC0 then
      break
    end
    cut = cut - 1
  end
  return text:sub(1, cut)
end

local function Stamp()
  return format("%s %.2f", date("%H:%M:%S"), GetTime())
end

local function Log(fmt, ...)
  local ok, text = pcall(format, fmt, ...)
  if not ok then
    text = fmt
  end
  local line = Stamp() .. " " .. text
  if not db then
    pending[#pending + 1] = line
    return
  end
  local log = db.log
  log[#log + 1] = line
  if #log > LOG_MAX then
    table.remove(log, 1)
  end
  if db.verbose then
    print("|cff66ccffSMP|r " .. text)
  end
end

-- Logs and prints to chat.
local function Say(fmt, ...)
  local ok, text = pcall(format, fmt, ...)
  if not ok then
    text = fmt
  end
  Log("%s", text)
  if not (db and db.verbose) then
    print("|cff66ccffSakaMind probe:|r " .. text)
  end
end

local function Safe(fn, ...)
  local ok, err = pcall(fn, ...)
  if not ok then
    Log("Lua error: %s", Show(err))
    if errorsShown < 3 then
      errorsShown = errorsShown + 1
      print("|cffff6666SakaMind probe error:|r " .. Show(err))
    end
  end
  return ok
end

local function After(seconds, fn, ...)
  local args = { ... }
  local count = select("#", ...)
  C_Timer.After(seconds, function()
    Safe(fn, unpack(args, 1, count))
  end)
end

-- Calls namespace[method](...) if it exists: ok, results... or false, "missing".
local function Try(namespace, method, ...)
  local fn = type(namespace) == "table" and namespace[method] or nil
  if type(fn) ~= "function" then
    return false, "missing"
  end
  return pcall(fn, ...)
end

local function EnumName(enum, value)
  if IsSecret(value) then
    return "<secret>"
  end
  if type(enum) == "table" then
    for name, other in pairs(enum) do
      if other == value then
        return name
      end
    end
  end
  return tostring(value)
end

local function SpellLabel(id)
  local name = WATCHED_CASTS[id]
  if not name then
    local ok, spellName = Try(C_Spell, "GetSpellName", id)
    name = ok and not IsSecret(spellName) and spellName or "?"
  end
  return format("%s %d", name, id)
end

-- Chat lock: true, false, or nil when unknown.
local function Locked()
  local ok, value = Try(C_ChatInfo, "InChatMessagingLockdown")
  if not ok or IsSecret(value) then
    return nil
  end
  return value and true or false
end

local function Phase()
  if encounter then
    return "boss"
  end
  return InCombatLockdown() and "trash" or "ooc"
end

local function EncounterTime()
  if encounter then
    return GetTime() - encounter.start
  end
end

local function Flags()
  local lock = Locked()
  return format("[chat lock %s, boss %s, combat %s]",
    lock == nil and "?" or (lock and "on" or "off"),
    encounter and "on" or "off",
    InCombatLockdown() and "on" or "off")
end

local function MyRealm()
  local realm = GetNormalizedRealmName and GetNormalizedRealmName()
  if IsSecret(realm) or not realm or realm == "" then
    realm = (GetRealmName() or ""):gsub("%s", "")
  end
  return realm
end

local function FullName(unit)
  local ok, name, realm = pcall(UnitFullName, unit)
  if not ok or IsSecret(name) or IsSecret(realm) or not name then
    return nil
  end
  if not realm or realm == "" then
    realm = MyRealm()
  end
  return name .. "-" .. realm
end

local function GroupChannel()
  return IsInRaid() and "RAID" or "PARTY"
end

local function MyGUID()
  if not myGUID then
    local guid = UnitGUID("player")
    if guid and not IsSecret(guid) then
      myGUID = guid
    end
  end
  return myGUID or "?"
end

-- Party members known to run the probe, as their peers entries. Party
-- GUIDs are read out of combat, so this works during fights too.
local function GroupPeers()
  local list = {}
  for _, unit in ipairs(PARTY_UNITS) do
    local guid = partyGUIDs[unit]
    if guid and peers[guid] then
      list[#list + 1] = peers[guid]
    end
  end
  return list
end

-- The party member's name for a GUID, as read out of combat.
local function NameForGUID(guid)
  for _, unit in ipairs(PARTY_UNITS) do
    if partyGUIDs[unit] and partyGUIDs[unit] == guid then
      return partyNames[unit]
    end
  end
end

-- Statistics --------------------------------------------------------------

local function PhaseStats(phase)
  local s = stats[phase]
  if not s then
    s = { sent = {}, recv = {} }
    stats[phase] = s
  end
  return s
end

local function CountSent(channel, result)
  local s = PhaseStats(Phase())
  local bucket = s.sent[channel]
  if not bucket then
    bucket = {}
    s.sent[channel] = bucket
  end
  bucket[result] = (bucket[result] or 0) + 1
end

local function CountReceived(channel)
  local s = PhaseStats(Phase())
  s.recv[channel] = (s.recv[channel] or 0) + 1
end

local function SummaryText(phase)
  local s = stats[phase]
  if not s then
    return nil
  end
  local sent = {}
  for channel, results in pairs(s.sent) do
    local parts = {}
    for result, count in pairs(results) do
      parts[#parts + 1] = format("%s x%d", result, count)
    end
    sent[#sent + 1] = channel .. " " .. table.concat(parts, "/")
  end
  local received = {}
  for channel, count in pairs(s.recv) do
    received[#received + 1] = format("%s %d", channel, count)
  end
  return format("sent: %s. Received: %s.",
    #sent > 0 and table.concat(sent, ", ") or "nothing",
    #received > 0 and table.concat(received, ", ") or "nothing")
end

-- Battle.net links ----------------------------------------------------------

local function FindGameAccount(guid, shortName)
  if guid and C_BattleNet and C_BattleNet.GetGameAccountInfoByGUID then
    local ok, info = pcall(C_BattleNet.GetGameAccountInfoByGUID, guid)
    if ok and type(info) == "table" and info.gameAccountID and not IsSecret(info.gameAccountID) then
      return info.gameAccountID, "GUID"
    end
  end
  if type(BNGetNumFriends) ~= "function" or not C_BattleNet
      or not C_BattleNet.GetFriendNumGameAccounts or not C_BattleNet.GetFriendGameAccountInfo then
    return nil
  end
  local ok, total = pcall(BNGetNumFriends)
  if not ok or IsSecret(total) then
    return nil
  end
  for i = 1, total or 0 do
    local okCount, count = pcall(C_BattleNet.GetFriendNumGameAccounts, i)
    if okCount and not IsSecret(count) then
      for j = 1, count or 0 do
        local okInfo, info = pcall(C_BattleNet.GetFriendGameAccountInfo, i, j)
        if okInfo and type(info) == "table" and info.gameAccountID and not IsSecret(info.gameAccountID)
            and not IsSecret(info.playerGuid) and not IsSecret(info.characterName) then
          if (guid and info.playerGuid == guid) or (shortName and info.characterName == shortName) then
            return info.gameAccountID, "friend list"
          end
        end
      end
    end
  end
end

local function UpdateRowNames()
  for unit, row in pairs(rows) do
    local name = partyNames[unit]
    row.name:SetText(name and name:match("^[^-]+") or "-")
  end
end

-- Reads party names, GUIDs and Battle.net links. Out of combat only.
local function RefreshParty(reason)
  if InCombatLockdown() then
    refreshAfterCombat = true
    return
  end
  refreshAfterCombat = false
  wipe(partyNames)
  wipe(partyGUIDs)
  wipe(links)
  local summary = {}
  for _, unit in ipairs(PARTY_UNITS) do
    if UnitExists(unit) then
      local full = FullName(unit)
      local guid = UnitGUID(unit)
      if IsSecret(guid) then
        guid = nil
      end
      partyNames[unit] = full
      partyGUIDs[unit] = guid
      if full then
        local id, how = FindGameAccount(guid, full:match("^[^-]+"))
        if guid then
          links[guid] = id
        end
        local label = format("%s (%s)", full, guid or "no GUID")
        summary[#summary + 1] = id and format("%s: Battle.net game account %s (found by %s)", label, Show(id), how)
          or format("%s: no Battle.net link (not Battle.net friends?)", label)
      end
    end
  end
  Log("party (%s): %s", reason, #summary > 0 and table.concat(summary, "; ") or "not in a party")
  UpdateRowNames()
end

-- Sending -------------------------------------------------------------------

-- protocol;kind;number;sender's chat lock (L, - or ?);sender's boss time;
-- sender's GUID, then ";text" for messages that carry text (the boss
-- results).
local function Payload(kind, text)
  seq = seq + 1
  local lock = Locked()
  local t = EncounterTime()
  local payload = format("%s;%s;%d;%s;%s;%s", PROTOCOL, kind, seq,
    lock == nil and "?" or (lock and "L" or "-"), t and format("%.1f", t) or "-", MyGUID())
  if text then
    payload = payload .. ";" .. text
  end
  return payload
end

local function SendAddon(kind, channel, target, text)
  local payload = Payload(kind, text)
  local ok, result = Try(C_ChatInfo, "SendAddonMessage", PREFIX, payload, channel, target)
  local name = ok and EnumName(Enum.SendAddonMessageResult, result) or ("error " .. Show(result))
  CountSent(channel, name)
  return format("#%d %s%s=%s", seq, channel, target and (" " .. target) or "", name)
end

local function SendBattleNet(kind, fullName, gameAccountID)
  local payload = Payload(kind)
  local ok, result = Try(C_BattleNet, "SendGameData", gameAccountID, PREFIX, payload)
  local name = ok and EnumName(Enum.SendAddonMessageResult, result) or ("error " .. Show(result))
  CountSent("BNET", name)
  return format("#%d BNET %s=%s", seq, fullName, name)
end

-- One round of test messages. A "hello" goes on the group channel only, so
-- other probes in the group learn about this one. Every other round goes
-- on every way there is: the group channel, plus a whisper and Battle.net
-- game data to each probe user in the group. Automatic rounds need such a
-- user, so a group without one gets nothing beyond the hello; a manual
-- /smp send before anyone is known tries every party member.
local function SendRound(kind)
  if not IsInGroup() then
    Log("send %s skipped: not in a group", kind)
    return
  end
  local targets = {}
  if kind ~= "hello" then
    targets = GroupPeers()
    if #targets == 0 then
      if kind ~= "manual" then
        Log("send %s skipped: no other probe user in the group %s", kind, Flags())
        return
      end
      for _, unit in ipairs(PARTY_UNITS) do
        if partyNames[unit] then
          targets[#targets + 1] = { guid = partyGUIDs[unit], name = partyNames[unit] }
        end
      end
    end
  end
  local parts = { SendAddon(kind, GroupChannel()) }
  if LE_PARTY_CATEGORY_INSTANCE and IsInGroup(LE_PARTY_CATEGORY_INSTANCE) then
    parts[#parts + 1] = SendAddon(kind, "INSTANCE_CHAT")
  end
  for _, peer in ipairs(targets) do
    parts[#parts + 1] = SendAddon(kind, "WHISPER", peer.name)
    local id = peer.guid and links[peer.guid]
    if id then
      parts[#parts + 1] = SendBattleNet(kind, peer.name, id)
    end
  end
  local line = table.concat(parts, ", ")
  Log("send %s: %s %s", kind, line, Flags())
  if kind == "boss" and not alerted.firstBossSend then
    alerted.firstBossSend = true
    Say("first send during the boss: %s", line)
  end
end

-- Boss results ------------------------------------------------------------------

-- This probe's results for the last boss, as short lines for the other
-- probe users: its messages during the boss, whether its own casts were
-- readable, and what its damage meter showed.
local function ResultLines()
  local own = lastBoss.own
  return {
    format("boss %s, %s after %.0f s", lastBoss.name, lastBoss.kind, lastBoss.lasted),
    "my messages during the boss, " .. lastBoss.traffic,
    format("my casts during the boss: %d readable, %d hidden; watched spells readable: %s",
      own.readable, own.hidden, #lastBoss.readable > 0 and table.concat(lastBoss.readable, ", ") or "none"),
    "my damage meter found: " .. (#meterFinds > 0 and table.concat(meterFinds, ", ") or "nothing"),
  }
end

-- Sends the results on the group channel, which reaches every probe user
-- in the group at once (four messages, well within the game's throttle).
-- Returns true if they went out.
local function SendResults(reason)
  if not lastBoss then
    return false
  end
  if not IsInGroup() or #GroupPeers() == 0 then
    resultsState = nil
    Log("boss results not sent (%s): no other probe user in the group", reason)
    return false
  end
  local lines = ResultLines()
  local parts = {}
  for i, line in ipairs(lines) do
    local text = format("%d/%d %s", i, #lines, line):gsub("[|;]", "/")
    parts[#parts + 1] = SendAddon("result", GroupChannel(), nil, Cut(text, 190))
  end
  resultsState = nil
  Log("sent my boss results (%s): %s %s", reason, table.concat(parts, ", "), Flags())
  return true
end

-- Sends the results if the chat lock is off; otherwise the end of the lock
-- sends them (see ADDON_RESTRICTION_STATE_CHANGED).
local function TrySendResults(reason)
  if not resultsState then
    return
  end
  if Locked() then
    resultsState = "due"
    Log("boss results wait for the chat lock to end")
    return
  end
  SendResults(reason)
end

-- Receiving -----------------------------------------------------------------

local function OnProbeMessage(channel, sender, text)
  if IsSecret(text) or IsSecret(sender) then
    Log("recv %s: the payload or sender is secret %s", channel, Flags())
    CountReceived(channel .. " (secret)")
    return
  end
  if type(sender) ~= "string" or type(text) ~= "string" then
    return
  end
  local protocol, kind, number, theirLock, theirTime, guid, rest = strsplit(";", text, 7)
  if protocol ~= PROTOCOL or not guid or guid == "" then
    Log("recv %s from %s: another probe version (protocol %s), ignored", channel, sender, Show(protocol))
    return
  end
  if guid == MyGUID() then
    Log("echo %s #%s %s %s", channel, Show(number), Show(kind), Flags())
    return
  end
  if channel == "BNET" then
    sender = NameForGUID(guid) or sender
  end
  local peer = peers[guid]
  if not peer then
    peer = { guid = guid, name = sender }
    peers[guid] = peer
    Log("new probe user %s (%s)", sender, guid)
  elseif channel ~= "BNET" then
    peer.name = sender -- the name the game uses for them, which whispers need
  end
  peer.lastSeen = GetTime()
  if kind == "result" then
    Log("results from %s: %s", sender, Show(rest))
    if type(rest) == "string" and rest:find("^1/") then
      Say("got %s's results for the last boss (saved in the log)", sender:match("^[^-]+"))
    end
    return
  end
  CountReceived(channel)
  local mine = EncounterTime()
  Log("recv %s from %s #%s %s: their chat lock %s, their boss time %s; my boss time %s %s",
    channel, sender, Show(number), Show(kind), Show(theirLock), Show(theirTime),
    mine and format("%.1f", mine) or "-", Flags())
  -- Answer a hello (at most every 10 s per player), so that a probe which
  -- joined or reloaded later learns about this one too.
  if kind == "hello" and (GetTime() - (helloAnswered[guid] or -100)) > 10 then
    local reply
    if channel == "PARTY" or channel == "RAID" or channel == "INSTANCE_CHAT" then
      reply = SendAddon("hello back", channel)
    elseif channel == "WHISPER" then
      reply = SendAddon("hello back", "WHISPER", sender)
    end
    if reply then
      helloAnswered[guid] = GetTime()
      Log("send hello back: %s %s", reply, Flags())
    end
  end
  if encounter and not alerted[channel] then
    alerted[channel] = true
    Say("|cff66ff66received a %s message during the boss|r from %s (#%s, sent at their boss time %s)",
      channel, sender, Show(number), Show(theirTime))
    PlaySoundFile(DING, "Master")
  end
end

-- Damage meter ----------------------------------------------------------------

local function MeterIcon(row, index, spellID)
  local texture = row and row.meter[index]
  if not texture then
    return
  end
  local ok, file = Try(C_Spell, "GetSpellTexture", spellID)
  if ok then
    pcall(texture.SetTexture, texture, file)
    texture:Show()
  end
end

local function ClearMeterIcons()
  for _, row in pairs(rows) do
    for _, texture in ipairs(row.meter) do
      texture:Hide()
    end
  end
end

-- Reads one party member's healing this fight from Blizzard's damage meter.
-- In combat the values may be secret: icons are then still shown (secret
-- spell IDs may be passed to GetSpellTexture), but nothing is compared.
local function CheckMeter(unit, when)
  local guid = partyGUIDs[unit]
  if not guid or not C_DamageMeter or not Enum.DamageMeterType then
    return
  end
  local row = rows[unit]
  local ok, source = Try(C_DamageMeter, "GetCombatSessionSourceFromType",
    Enum.DamageMeterSessionType.Current, Enum.DamageMeterType.HealingDone, guid)
  local status
  if not ok then
    status = "error " .. Show(source)
  elseif IsSecret(source) then
    status = "the whole entry is secret"
  elseif type(source) ~= "table" then
    status = "no data"
  else
    local spells = source.combatSpells
    if IsSecret(spells) then
      status = "the spell list is secret"
    elseif type(spells) ~= "table" then
      status = "no spell list"
    else
      local count = #spells
      if IsSecret(count) then
        status = "the number of spells is secret"
      else
        local hidden, readable = 0, {}
        for i = 1, count do
          local entry = spells[i]
          local id
          if not IsSecret(entry) and type(entry) == "table" then
            id = entry.spellID
          end
          if IsSecret(entry) or IsSecret(id) then
            hidden = hidden + 1
          elseif id then
            readable[#readable + 1] = SpellLabel(id)
            local key = unit .. ":" .. id
            if METER_SPELLS[id] and not meterSeen[key] then
              meterSeen[key] = true
              meterFinds[#meterFinds + 1] = format("%s for %s (%s)", METER_SPELLS[id],
                (partyNames[unit] or unit):match("^[^-]+"), when)
              Say("|cff66ff66damage meter shows %s for %s|r (%s) %s",
                METER_SPELLS[id], partyNames[unit] or unit, when, Flags())
              PlaySoundFile(DING, "Master")
            end
          end
          if i <= METER_ICONS then
            MeterIcon(row, i, id)
          end
        end
        if row then
          for i = count + 1, METER_ICONS do
            row.meter[i]:Hide()
          end
        end
        status = format("%d spells, %d with hidden IDs%s", count, hidden,
          #readable > 0 and (": " .. table.concat(readable, ", ")) or "")
      end
    end
  end
  if status ~= meterStatus[unit] then
    meterStatus[unit] = status
    Log("damage meter %s (%s), %s: %s %s", unit, partyNames[unit] or "?", when, status, Flags())
  end
end

local function CheckAllMeters(when)
  for _, unit in ipairs(PARTY_UNITS) do
    CheckMeter(unit, when)
  end
end

-- Own casts -------------------------------------------------------------------

local function CountOwnCast(readable)
  local phase = Phase()
  local bucket = ownCasts[phase]
  if not bucket then
    bucket = { readable = 0, hidden = 0 }
    ownCasts[phase] = bucket
  end
  if readable then
    bucket.readable = bucket.readable + 1
  else
    bucket.hidden = bucket.hidden + 1
  end
end

local function LogOwnCasts()
  for phase, bucket in pairs(ownCasts) do
    if phase ~= "ooc" then
      Log("your casts during %s: %d with a readable spell ID, %d hidden", phase, bucket.readable, bucket.hidden)
    end
  end
  wipe(ownCasts)
end

-- Party casts -----------------------------------------------------------------

-- Party members' casts: do they reach add-ons in combat and during a boss,
-- and with a hidden spell ID? For each hidden ID the probe also tries the
-- calls a display would need that never reads the spell: Blizzard's yes/no
-- spell checks, an alpha set from such an answer, a status bar fed the ID,
-- the spell's details, and a curve (which the docs say refuses hidden
-- values from add-ons). Nothing is shown, and no answer is looked at; the
-- probe only counts whether each call was accepted.

local HIDDEN_CALLS = {
  "IsSpellImportant", "AuraIsBigDefensive", "IsSpellHelpful", "SetAlphaFromBoolean",
  "StatusBar:SetValue", "GetSpellInfo", "SetAlpha(cast time)", "curve:Evaluate",
}
-- phase -> { casts, hidden, units = { unit -> casts }, calls = { name -> { ok, refused, err } } }
local partyCasts = {}
local testFrame, testTexture, testBar, testCurve

local function TestObjects()
  if testFrame then
    return
  end
  testFrame = CreateFrame("Frame")
  testFrame:Hide()
  testTexture = testFrame:CreateTexture()
  testBar = CreateFrame("StatusBar", nil, testFrame)
  testBar:SetMinMaxValues(0, 1)
  local ok, curve = Try(C_CurveUtil, "CreateCurve")
  if ok and curve then
    testCurve = curve
    pcall(curve.AddPoint, curve, 0, 0)
    pcall(curve.AddPoint, curve, 1, 1)
  end
end

local function Record(bucket, name, ok, err)
  local call = bucket.calls[name]
  if not call then
    call = { ok = 0, refused = 0 }
    bucket.calls[name] = call
  end
  if ok then
    call.ok = call.ok + 1
  else
    call.refused = call.refused + 1
    call.err = call.err or Cut(Show(err), 120)
  end
end

-- Tries each call with a hidden spell ID. What comes back may be secret;
-- it is only passed on, never compared.
local function TryHiddenID(bucket, spellID)
  TestObjects()
  local ok, answer = Try(C_Spell, "IsSpellImportant", spellID)
  Record(bucket, "IsSpellImportant", ok, answer)
  if ok and (IsSecret(answer) or answer ~= nil) then
    Record(bucket, "SetAlphaFromBoolean", pcall(testFrame.SetAlphaFromBoolean, testFrame, answer))
  end
  Record(bucket, "AuraIsBigDefensive", Try(C_UnitAuras, "AuraIsBigDefensive", spellID))
  Record(bucket, "IsSpellHelpful", Try(C_Spell, "IsSpellHelpful", spellID))
  Record(bucket, "StatusBar:SetValue", pcall(testBar.SetValue, testBar, spellID))
  local info
  ok, info = Try(C_Spell, "GetSpellInfo", spellID)
  Record(bucket, "GetSpellInfo", ok, info)
  if ok and not IsSecret(info) and type(info) == "table" then
    Record(bucket, "SetAlpha(cast time)", pcall(testTexture.SetAlpha, testTexture, info.castTime))
  end
  if testCurve then
    Record(bucket, "curve:Evaluate", pcall(testCurve.Evaluate, testCurve, spellID))
  end
end

local function OnPartyCast(unit, spellID)
  local phase = Phase()
  local bucket = partyCasts[phase]
  if not bucket then
    bucket = { casts = 0, hidden = 0, units = {}, calls = {} }
    partyCasts[phase] = bucket
  end
  bucket.casts = bucket.casts + 1
  bucket.units[unit] = (bucket.units[unit] or 0) + 1
  if IsSecret(spellID) then
    bucket.hidden = bucket.hidden + 1
    TryHiddenID(bucket, spellID)
  end
end

-- "IsSpellImportant accepted (12); curve:Evaluate refused (12): error", and
-- how many of the calls tried were always accepted.
local function HiddenCallText(bucket)
  local parts, accepted, tried = {}, 0, 0
  for _, name in ipairs(HIDDEN_CALLS) do
    local call = bucket.calls[name]
    if call then
      tried = tried + 1
      if call.refused == 0 then
        accepted = accepted + 1
        parts[#parts + 1] = format("%s accepted (%d)", name, call.ok)
      elseif call.ok == 0 then
        parts[#parts + 1] = format("%s refused (%d): %s", name, call.refused, call.err)
      else
        parts[#parts + 1] = format("%s accepted %d, refused %d: %s", name, call.ok, call.refused, call.err)
      end
    end
  end
  return table.concat(parts, "; "), accepted, tried
end

-- Logs one phase's party casts and starts that phase afresh. For a boss
-- the result goes to chat too: it says whether a display can follow a
-- party member's casts mid-fight. Out of combat it's logged only when some
-- spell ID was hidden.
local function ReportPartyCasts(phase, lasted)
  local bucket = partyCasts[phase]
  partyCasts[phase] = nil
  if not bucket then
    if phase == "boss" and IsInGroup() and (lasted or 0) > 10 then
      Say("party casts during the boss: none reached the probe")
    end
    return
  end
  if phase == "ooc" and bucket.hidden == 0 then
    return
  end
  local units = {}
  for _, unit in ipairs(PARTY_UNITS) do
    if bucket.units[unit] then
      units[#units + 1] = format("%s %d", partyNames[unit] or unit, bucket.units[unit])
    end
  end
  Log("party casts during %s: %d, %d with a hidden spell ID (%s)", phase, bucket.casts, bucket.hidden,
    table.concat(units, ", "))
  if bucket.hidden == 0 then
    if phase == "boss" then
      Say("party casts during the boss: %d, none with a hidden spell ID", bucket.casts)
    end
    return
  end
  local text, accepted, tried = HiddenCallText(bucket)
  Log("calls with hidden spell IDs during %s: %s", phase, text)
  if phase == "boss" then
    Say("party casts during the boss: %d, %d with a hidden spell ID. %d of %d test calls accepted them (details in the log).",
      bucket.casts, bucket.hidden, accepted, tried)
  end
end

-- Secrecy -----------------------------------------------------------------------

local SECRECY = { [0] = "never hidden", [1] = "always hidden", [2] = "hidden in combat" }

local function SecrecyName(ok, level)
  if not ok then
    return "?"
  end
  if IsSecret(level) then
    return "<secret>"
  end
  return SECRECY[level] or tostring(level)
end

-- Logs how hidden each spell's aura and cast are (0 never, 1 always,
-- 2 depending on combat and encounters), and says which are never hidden.
local function SecrecyReport()
  local never = {}
  local lists = { DEFENSIVES, OTHER_CASTS, { FORBEARANCE } }
  for _, list in ipairs(lists) do
    for _, spell in ipairs(list) do
      local parts = {}
      for _, id in ipairs(spell.ids) do
        local okAura, aura = Try(C_Secrets, "GetSpellAuraSecrecy", id)
        local okCast, cast = Try(C_Secrets, "GetSpellCastSecrecy", id)
        local auraName, castName = SecrecyName(okAura, aura), SecrecyName(okCast, cast)
        parts[#parts + 1] = format("%d aura %s, cast %s", id, auraName, castName)
        if auraName == SECRECY[0] then
          never[#never + 1] = format("%s aura %d", spell.name, id)
        end
        if castName == SECRECY[0] then
          never[#never + 1] = format("%s cast %d", spell.name, id)
        end
      end
      Log("secrecy %s: %s", spell.name, table.concat(parts, "; "))
    end
  end
  Say("never hidden: %s", #never > 0 and table.concat(never, ", ") or "none of the probe's spells")
end

-- Flag check ------------------------------------------------------------------------

-- Blizzard's yes/no spell checks that accept a hidden spell ID from add-on
-- code, plus spell details a widget can take. If some combination answers
-- differently for Lay on Hands than for every other spell a paladin casts,
-- a display could reveal a countdown only on the cast that was Lay on
-- Hands, without reading which spell it was. /smp flags records every
-- spell's answers out of combat, where IDs are readable, in
-- SakaMindProbeDB.flags: one number per spell, one bit per answer (legend
-- in .bits).

local FLAG_CHECKS = {
  { "important", C_Spell, "IsSpellImportant" },
  { "big defensive", C_UnitAuras, "AuraIsBigDefensive" },
  { "helpful", C_Spell, "IsSpellHelpful" },
  { "harmful", C_Spell, "IsSpellHarmful" },
  { "has range", C_Spell, "SpellHasRange" },
  { "consumable", C_Spell, "IsConsumableSpell" },
  { "passive", C_Spell, "IsSpellPassive" },
  { "private aura", C_UnitAuras, "AuraIsPrivate" },
  { "click-bindable", C_ClickBindings, "CanSpellBeClickBound" },
}
local FLAG_DETAILS = { "cast time", "min range", "max range", "power cost" }
-- The spell ID ranges that hold Forever's spells (wago.tools SpellName,
-- build 70888, with a margin).
local FLAG_RANGES = {
  { 1, 105000 }, { 134000, 184000 }, { 219000, 220000 },
  { 240000, 262000 }, { 285000, 475000 }, { 1213000, 1331000 },
}
local FLAG_STEP = 4000 -- spell IDs checked per frame
local flagScan -- the running check: { range, id, sig, count, started, ticker }

local function Positive(value)
  return not IsSecret(value) and type(value) == "number" and value > 0
end

local function FlagNames()
  local names = {}
  for _, check in ipairs(FLAG_CHECKS) do
    names[#names + 1] = check[1]
  end
  for _, detail in ipairs(FLAG_DETAILS) do
    names[#names + 1] = detail
  end
  return names
end

-- One spell's answers as a number: bit 1 for the first name in
-- FlagNames(), 2 for the second, and so on.
local function SpellMask(id)
  local mask, weight = 0, 1
  for _, check in ipairs(FLAG_CHECKS) do
    local ok, answer = Try(check[2], check[3], id)
    if ok and not IsSecret(answer) and answer == true then
      mask = mask + weight
    end
    weight = weight * 2
  end
  local details = { false, false, false, false }
  local ok, info = Try(C_Spell, "GetSpellInfo", id)
  if ok and not IsSecret(info) and type(info) == "table" then
    details[1] = Positive(info.castTime)
    details[2] = Positive(info.minRange)
    details[3] = Positive(info.maxRange)
  end
  local costs
  ok, costs = Try(C_Spell, "GetSpellPowerCost", id)
  if ok and not IsSecret(costs) and type(costs) == "table" then
    for _, cost in ipairs(costs) do
      if type(cost) == "table" and (Positive(cost.cost) or Positive(cost.minCost) or Positive(cost.costPercent)) then
        details[4] = true
      end
    end
  end
  for _, set in ipairs(details) do
    if set then
      mask = mask + weight
    end
    weight = weight * 2
  end
  return mask
end

-- "helpful, has range, max range" for a mask.
local function MaskText(mask)
  local set, weight = {}, 1
  for _, name in ipairs(FlagNames()) do
    if mask % (weight * 2) >= weight then
      set[#set + 1] = name
    end
    weight = weight * 2
  end
  return #set > 0 and table.concat(set, ", ") or "no flag set"
end

local function FinishFlags()
  local scan = flagScan
  flagScan = nil
  scan.ticker:Cancel()
  local legend = {}
  for i, name in ipairs(FlagNames()) do
    legend[#legend + 1] = format("%d %s", 2 ^ (i - 1), name)
  end
  local version, build = GetBuildInfo()
  db.flags = {
    date = date("%Y-%m-%d %H:%M"),
    build = format("%s (%s)", Show(version), Show(build)),
    bits = table.concat(legend, ", "),
    spells = scan.count,
    seconds = GetTime() - scan.started,
    sig = scan.sig,
  }
  local important, big = 0, 0
  for _, mask in pairs(scan.sig) do
    if mask % 2 == 1 then
      important = important + 1
    end
    if mask % 4 >= 2 then
      big = big + 1
    end
  end
  for _, id in ipairs({ 633, 2800, 10310 }) do
    local mask = scan.sig[id]
    if mask then
      local twins = 0
      for other, otherMask in pairs(scan.sig) do
        if otherMask == mask and not LAY_ON_HANDS_IDS[other] then
          twins = twins + 1
        end
      end
      Say("Lay on Hands %d: %s. %d other spells answer every check the same way.", id, MaskText(mask), twins)
    else
      Say("Lay on Hands %d: not found", id)
    end
  end
  Say("flag check done: %d spells in %.0f s, %d marked important, %d big defensives. /reload to save the results.",
    scan.count, db.flags.seconds, important, big)
end

local function FlagStep()
  local scan = flagScan
  if not scan then
    return
  end
  if InCombatLockdown() then
    scan.ticker:Cancel()
    flagScan = nil
    Say("flag check stopped because combat started; run /smp flags again out of combat")
    return
  end
  local exists = C_Spell.DoesSpellExist
  for _ = 1, FLAG_STEP do
    local range = FLAG_RANGES[scan.range]
    if not range then
      FinishFlags()
      return
    end
    local id = scan.id
    if id > range[2] then
      scan.range = scan.range + 1
      scan.id = FLAG_RANGES[scan.range] and FLAG_RANGES[scan.range][1] or 0
    else
      scan.id = id + 1
      local ok, found = pcall(exists, id)
      if ok and found == true then
        scan.sig[id] = SpellMask(id)
        scan.count = scan.count + 1
      end
    end
  end
end

local function StartFlags()
  if flagScan then
    Say("the flag check is already running")
    return
  end
  if InCombatLockdown() then
    Say("run the flag check out of combat")
    return
  end
  if not (C_Spell and C_Spell.DoesSpellExist) then
    Say("this client has no C_Spell.DoesSpellExist, so the flag check can't run")
    return
  end
  flagScan = { range = 1, id = FLAG_RANGES[1][1], sig = {}, count = 0, started = GetTime() }
  Say("checking the flags of every spell; it takes a few seconds, stay out of combat")
  flagScan.ticker = C_Timer.NewTicker(0.01, function()
    if not Safe(FlagStep) and flagScan then
      flagScan.ticker:Cancel()
      flagScan = nil
      Say("the flag check stopped on an error (see the log)")
    end
  end)
end

-- Aura sounds -----------------------------------------------------------------

-- A "ding" when a defensive lands on you or a party member. Registering is
-- refused during the chat lock (DBM's experience), so it happens out of
-- combat and is redone when the group changes.
local function RegisterSounds(reason)
  if InCombatLockdown() or Locked() then
    Log("aura sounds (%s): waiting until combat and the chat lock end", reason)
    return
  end
  for _, id in ipairs(soundIDs) do
    Try(C_UnitAuras, "RemoveAuraSound", id)
  end
  wipe(soundIDs)
  local trigger = Enum.UnitAuraSoundTrigger and Enum.UnitAuraSoundTrigger.Added or 0
  local registered, refused, problem = 0, 0, nil
  for _, unit in ipairs({ "player", "party1", "party2", "party3", "party4" }) do
    for _, spell in ipairs(DEFENSIVES) do
      if spell.sound then
        for _, id in ipairs(spell.sound == true and spell.ids or spell.sound) do
          local ok, soundID = Try(C_UnitAuras, "AddAuraSound", trigger, {
            unitToken = unit,
            spellID = id,
            soundFileID = DING,
            outputChannel = "Master",
            throttleSeconds = 2,
          })
          if ok and soundID and not IsSecret(soundID) then
            registered = registered + 1
            soundIDs[#soundIDs + 1] = soundID
          else
            refused = refused + 1
            problem = problem or (ok and "no ID returned" or Show(soundID))
          end
        end
      end
    end
  end
  Log("aura sounds (%s): %d registered, %d refused%s", reason, registered, refused,
    problem and (", first problem: " .. problem) or "")
end

-- Panel ---------------------------------------------------------------------------

local containersAvailable
local function ContainersAvailable()
  if containersAvailable == nil then
    containersAvailable = false
    if C_AddOns and C_AddOns.IsAddOnLoaded and not C_AddOns.IsAddOnLoaded("Blizzard_AuraContainer") then
      pcall(C_AddOns.LoadAddOn, "Blizzard_AuraContainer")
    end
    if AuraContainerSortMethod then
      containersAvailable = pcall(function()
        local test = CreateFrame("AuraContainer", nil, UIParent, "CustomAuraContainerTemplate")
        test:Hide()
      end)
    end
    Log("aura containers available: %s", tostring(containersAvailable))
  end
  return containersAvailable
end

local function StyleIcon(button, size)
  button:SetSize(size, size)
  button:EnableMouse(false)
  local icon = button:CreateTexture(nil, "ARTWORK")
  icon:SetAllPoints()
  icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
  button:SetIcon(icon)
  local cooldown = CreateFrame("Cooldown", nil, button, "CooldownFrameTemplate")
  cooldown:SetAllPoints()
  cooldown:SetReverse(true)
  cooldown:SetDrawEdge(false)
  cooldown:SetHideCountdownNumbers(true)
  button:SetDurationCooldown(cooldown)
  local text = button:CreateFontString(nil, "OVERLAY")
  text:SetFont(FONT, 9, "OUTLINE")
  text:SetPoint("CENTER", 0, 0)
  button:SetDurationText(text, {})
end

local function MakeContainer(unit, key, filter, spellIDs, max, x, y)
  local container = CreateFrame("AuraContainer", nil, panel, "CustomAuraContainerTemplate")
  container:SetEnabled(false)
  container:SetPoint("TOPLEFT", panel, "TOPLEFT", x, y)
  container:SetFlowLayoutAnchorPoint("TOPLEFT")
  if AnchorUtil and AnchorUtil.FlowDirection then
    pcall(container.SetFlowLayoutGrowthDirection, container, AnchorUtil.FlowDirection.Right,
      AnchorUtil.FlowDirection.Down)
  end
  container:AddAuraGroup(key, filter, {
    maxFrameCount = max,
    candidateFilters = { includeSpellIDs = spellIDs },
    sortMethod = AuraContainerSortMethod.Default,
    layout = { elementWidth = ICON, elementHeight = ICON, elementSpacing = 2, lineSpacing = 2,
      groupSpacing = 2, layoutIndex = 1 },
    initializeFrame = function(button)
      local ok, err = pcall(StyleIcon, button, ICON)
      if not ok then
        Log("aura icon setup failed: %s", Show(err))
      end
    end,
  })
  container:SetAuraGroupEnabled(key, true)
  container:SetUnit(unit)
  container:SetEnabled(true)
  return container
end

local function Label(text, x, y, size)
  local label = panel:CreateFontString(nil, "OVERLAY")
  label:SetFont(FONT, size or 10, "OUTLINE")
  label:SetPoint("TOPLEFT", panel, "TOPLEFT", x, y)
  label:SetJustifyH("LEFT")
  label:SetText(text)
  return label
end

local function StatusText()
  local lock = Locked()
  return format("chat lock %s   boss %s   combat %s   probe users in group %d",
    lock == nil and "?" or (lock and "|cffff6666on|r" or "|cff66ff66off|r"),
    encounter and format("%s %.0fs", encounter.name, GetTime() - encounter.start) or "-",
    InCombatLockdown() and "yes" or "no", #GroupPeers())
end

-- The panel holds aura containers, so it's shown or hidden out of combat
-- only. The choice is kept across sessions.
local function SetPanelShown(shown)
  if InCombatLockdown() then
    Say("the panel can be shown or hidden only out of combat")
    return
  end
  db.shown = shown
  if panel then
    panel:SetShown(shown)
  end
  if not shown then
    Say("panel hidden; /smp show brings it back")
  end
end

-- A small close button in the panel's top right corner.
local function AddCloseButton()
  local ok, close = pcall(CreateFrame, "Button", nil, panel, "UIPanelCloseButton")
  if not ok then
    close = CreateFrame("Button", nil, panel)
    local x = close:CreateFontString(nil, "OVERLAY")
    x:SetFont(FONT, 12, "OUTLINE")
    x:SetPoint("CENTER")
    x:SetText("x")
  end
  close:SetSize(20, 20)
  close:SetPoint("TOPRIGHT", panel, "TOPRIGHT", 0, 0)
  close:SetScript("OnClick", function()
    Safe(SetPanelShown, false)
  end)
end

local function BuildPanel()
  if panel or InCombatLockdown() then
    return
  end
  panel = CreateFrame("Frame", "SakaMindProbePanel", UIParent)
  panel:SetSize(400, 58 + #PARTY_UNITS * 26)
  panel:SetFrameStrata("MEDIUM")
  local pos = db.pos
  if pos then
    panel:SetPoint(pos[1], UIParent, pos[2], pos[3], pos[4])
  else
    panel:SetPoint("TOP", UIParent, "TOP", 0, -140)
  end
  local background = panel:CreateTexture(nil, "BACKGROUND")
  background:SetAllPoints()
  background:SetColorTexture(0, 0, 0, 0.6)
  panel:EnableMouse(true)
  panel:SetMovable(true)
  panel:SetClampedToScreen(true)
  panel:RegisterForDrag("LeftButton")
  panel:SetScript("OnDragStart", function(self)
    if not InCombatLockdown() then
      self:StartMoving()
    end
  end)
  panel:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    local point, _, relativePoint, x, y = self:GetPoint(1)
    db.pos = { point, relativePoint, x, y }
  end)

  Label("SakaMind probe  (/smp for commands)", 6, -5, 11)
  AddCloseButton()
  panel.status = Label("", 6, -20)
  Label("Defensives now", 100, -36, 9)
  Label("Forb.", 222, -36, 9)
  Label("Healing this fight (damage meter)", 252, -36, 9)

  local containers = ContainersAvailable()
  local defensiveIDs, forbearanceIDs = TrueSet(DEFENSIVES), TrueSet({ FORBEARANCE })
  for index, unit in ipairs(PARTY_UNITS) do
    local y = -50 - (index - 1) * 26
    local row = { unit = unit, meter = {} }
    row.name = Label("-", 6, y - 5, 10)
    row.name:SetWidth(90)
    if containers then
      local ok, container = pcall(MakeContainer, unit, "defensives", "HELPFUL", defensiveIDs, 5, 100, y)
      if ok then
        row.defensives = container
      else
        Log("defensive aura container for %s failed: %s", unit, Show(container))
      end
      ok, container = pcall(MakeContainer, unit, "forbearance", "HARMFUL", forbearanceIDs, 1, 222, y)
      if ok then
        row.forbearance = container
      else
        Log("Forbearance aura container for %s failed: %s", unit, Show(container))
      end
    end
    for i = 1, METER_ICONS do
      local texture = panel:CreateTexture(nil, "ARTWORK")
      texture:SetSize(ICON - 2, ICON - 2)
      texture:SetPoint("TOPLEFT", panel, "TOPLEFT", 252 + (i - 1) * ICON, y - 1)
      texture:SetTexCoord(0.08, 0.92, 0.08, 0.92)
      texture:Hide()
      row.meter[i] = texture
    end
    rows[unit] = row
  end

  local elapsedSince = 0
  panel:SetScript("OnUpdate", function(self, elapsed)
    elapsedSince = elapsedSince + elapsed
    if elapsedSince >= 0.5 then
      elapsedSince = 0
      self.status:SetText(StatusText())
    end
  end)
  panel:SetShown(db.shown)
  UpdateRowNames()
end


-- Session report ----------------------------------------------------------------

local function ReportClient()
  local version, build = GetBuildInfo()
  local _, class = UnitClass("player")
  local okRestricted, restricted = Try(C_ChatInfo, "AreOutgoingAddonChatMessagesRestricted")
  local okMeter, meterAvailable, meterReason = Try(C_DamageMeter, "IsDamageMeterAvailable")
  local okTrial, trial = pcall(function() return IsTrialAccount and IsTrialAccount() end)
  local okVeteran, veteran = pcall(function() return IsVeteranTrialAccount and IsVeteranTrialAccount() end)
  local okAddon, addonVersion = Try(C_AddOns, "GetAddOnMetadata", ADDON_NAME, "Version")
  Log("---- session: %s %s, client %s (%s), %s, %s ----", ADDON_NAME,
    okAddon and Show(addonVersion) or "?", Show(version), Show(build), Show(FullName("player")), Show(class))
  Log("trial account %s, veteran account %s, add-ons barred from sending chat messages (not add-on messages) on this realm %s",
    okTrial and Show(trial) or "?", okVeteran and Show(veteran) or "?",
    okRestricted and Show(restricted) or "?")
  Log("damage meter available %s%s, damageMeterEnabled %s",
    okMeter and Show(meterAvailable) or "?",
    okMeter and meterReason and meterReason ~= "" and (" (" .. Show(meterReason) .. ")") or "",
    Show(GetCVar and GetCVar("damageMeterEnabled")))
  Log("APIs: SendGameData %s, AddAuraSound %s, GetSpellAuraSecrecy %s, GetCombatSessionSourceFromType %s",
    tostring(C_BattleNet ~= nil and C_BattleNet.SendGameData ~= nil),
    tostring(C_UnitAuras ~= nil and C_UnitAuras.AddAuraSound ~= nil),
    tostring(C_Secrets ~= nil and C_Secrets.GetSpellAuraSecrecy ~= nil),
    tostring(C_DamageMeter ~= nil and C_DamageMeter.GetCombatSessionSourceFromType ~= nil))
end

-- Events ------------------------------------------------------------------------

local events = CreateFrame("Frame")
local handlers = {}

local rosterQueued = false
local lastHello = 0
local function OnGroupChanged(reason)
  rosterQueued = false
  RefreshParty(reason)
  RegisterSounds(reason)
  if IsInGroup() and not Locked() and GetTime() - lastHello > 20 then
    lastHello = GetTime()
    SendRound("hello")
  end
end

local function QueueGroupChanged(reason)
  if rosterQueued then
    return
  end
  rosterQueued = true
  After(3, OnGroupChanged, reason)
end

function handlers.ADDON_LOADED(name)
  if name ~= ADDON_NAME then
    return
  end
  SakaMindProbeDB = SakaMindProbeDB or {}
  db = SakaMindProbeDB
  db.log = db.log or {}
  if db.shown == nil then
    db.shown = true
  end
  for _, line in ipairs(pending) do
    db.log[#db.log + 1] = line
  end
  wipe(pending)
  ReportClient()
end

function handlers.PLAYER_LOGIN()
  local ok, result = Try(C_ChatInfo, "RegisterAddonMessagePrefix", PREFIX)
  Log("add-on message prefix %s registered: %s", PREFIX,
    ok and EnumName(Enum.RegisterAddonMessagePrefixResult, result) or ("error " .. Show(result)))
  BuildPanel()
  After(4, OnGroupChanged, "login")
  After(8, SecrecyReport)
end

function handlers.PLAYER_ENTERING_WORLD()
  QueueGroupChanged("entering world")
end

function handlers.GROUP_ROSTER_UPDATE()
  QueueGroupChanged("group changed")
end

local bnetQueued = false
function handlers.BN_FRIEND_INFO_CHANGED()
  if bnetQueued then
    return
  end
  bnetQueued = true
  After(5, function()
    bnetQueued = false
    RefreshParty("Battle.net friends changed")
  end)
end

function handlers.ENCOUNTER_START(_, name)
  encounter = { name = Show(name), start = GetTime() }
  stats.boss = nil
  partyCasts.boss = nil
  wipe(alerted)
  wipe(bossReadable)
  wipe(meterFinds)
  if encounterTicker then
    encounterTicker:Cancel()
    encounterTicker = nil
  end
  local count = #GroupPeers()
  if count == 0 then
    Say("boss pull: %s. No other probe user in the group, so no test messages. %s", encounter.name, Flags())
    return
  end
  Say("boss pull: %s. Sending test messages to %d probe user(s) every %d s. %s",
    encounter.name, count, SEND_EVERY, Flags())
  After(2, SendRound, "boss")
  encounterTicker = C_Timer.NewTicker(SEND_EVERY, function()
    Safe(SendRound, "boss")
  end)
end

function handlers.ENCOUNTER_END(_, name, _, _, success)
  if encounterTicker then
    encounterTicker:Cancel()
    encounterTicker = nil
  end
  local kind = (not IsSecret(success) and success == 1) and "kill" or "wipe"
  local lasted = encounter and (GetTime() - encounter.start) or 0
  Log("boss end: %s, %s after %.0f s %s", Show(name), kind, lasted, Flags())
  ReportPartyCasts("boss", lasted)
  CheckAllMeters("boss end")
  -- Keep this boss's results for the other probe users; they go out in
  -- 15 s, or when the chat lock ends if it's still on then.
  local own = ownCasts.boss or { readable = 0, hidden = 0 }
  local readable = {}
  for spellName in pairs(bossReadable) do
    readable[#readable + 1] = spellName
  end
  table.sort(readable)
  lastBoss = {
    name = Show(name),
    kind = kind,
    lasted = lasted,
    own = { readable = own.readable, hidden = own.hidden },
    readable = readable,
    traffic = SummaryText("boss") or "nothing sent or received",
  }
  resultsState = "waiting"
  After(15, TrySendResults, "after the boss")
  encounter = nil
  After(0.5, SendRound, kind)
  After(3, SendRound, kind)
  After(10, SendRound, kind)
  After(14, function()
    local summary = SummaryText("boss")
    if summary then
      Say("boss summary, %s", summary)
    else
      Log("boss summary: nothing sent or received")
    end
  end)
end

function handlers.PLAYER_REGEN_DISABLED()
  ReportPartyCasts("ooc")
  ClearMeterIcons()
  wipe(meterSeen)
  wipe(meterStatus)
  if meterTicker then
    meterTicker:Cancel()
  end
  meterTicker = C_Timer.NewTicker(METER_EVERY, function()
    Safe(CheckAllMeters, "in combat")
  end)
  if not encounter then
    stats.trash = nil
    After(2, function()
      if InCombatLockdown() and not encounter then
        SendRound("trash")
      end
    end)
  end
end

function handlers.PLAYER_REGEN_ENABLED()
  if meterTicker then
    meterTicker:Cancel()
    meterTicker = nil
  end
  After(1, function()
    if not panel then
      BuildPanel()
    end
    CheckAllMeters("after combat")
    LogOwnCasts()
    ReportPartyCasts("trash")
    if refreshAfterCombat then
      OnGroupChanged("after combat")
    end
    if stats.trash then
      Log("trash summary, %s", SummaryText("trash"))
      stats.trash = nil
    end
  end)
end

local lastMeterEvent = 0
function handlers.DAMAGE_METER_CURRENT_SESSION_UPDATED()
  if InCombatLockdown() and GetTime() - lastMeterEvent > 1.5 then
    lastMeterEvent = GetTime()
    CheckAllMeters("update event")
  end
end

function handlers.ADDON_RESTRICTION_STATE_CHANGED(kind, state)
  local kindName = EnumName(Enum.AddOnRestrictionType, kind)
  local stateName = EnumName(Enum.AddOnRestrictionState, state)
  Log("restriction %s: %s %s", kindName, stateName, Flags())
  if kindName == "Chat" then
    if stateName == "Activating" then
      -- The moment before the lock: can a last message still go out?
      SendRound("lock starting")
    elseif stateName == "Inactive" then
      SendRound("lock ended")
      RegisterSounds("chat lock ended")
      if resultsState == "due" then
        After(2, TrySendResults, "chat lock ended")
      end
    end
  end
end

function handlers.CHAT_MSG_ADDON(prefix, text, channel, sender)
  if IsSecret(prefix) then
    Log("CHAT_MSG_ADDON with a secret prefix %s", Flags())
    return
  end
  if prefix == PREFIX then
    OnProbeMessage(IsSecret(channel) and "?" or channel, sender, text)
  end
end

function handlers.BN_CHAT_MSG_ADDON(prefix, text, _, senderID)
  if IsSecret(prefix) then
    Log("BN_CHAT_MSG_ADDON with a secret prefix %s", Flags())
    return
  end
  if prefix == PREFIX then
    OnProbeMessage("BNET", "game account " .. Show(senderID), text)
  end
end

function handlers.UNIT_SPELLCAST_SUCCEEDED(_, _, spellID)
  if IsSecret(spellID) then
    CountOwnCast(false)
    return
  end
  CountOwnCast(true)
  local name = WATCHED_CASTS[spellID]
  if name then
    local phase = Phase()
    if phase == "boss" then
      bossReadable[name] = true
    end
    Log("your %s (%d) cast had a readable spell ID, during %s %s", name, spellID, phase, Flags())
    if phase ~= "ooc" then
      Say("your %s cast was readable during %s", name, phase == "boss" and "the boss" or "combat")
    end
  end
end

events:SetScript("OnEvent", function(_, event, ...)
  local handler = handlers[event]
  if handler then
    Safe(handler, ...)
  end
end)

for event in pairs(handlers) do
  if event == "UNIT_SPELLCAST_SUCCEEDED" then
    local ok = pcall(events.RegisterUnitEvent, events, event, "player")
    if not ok then
      Log("could not register %s", event)
    end
  elseif not pcall(events.RegisterEvent, events, event) then
    Log("could not register %s", event)
  end
end

-- One frame per party slot, so the unit is known without reading the
-- event's own unit argument, which may be secret.
for _, unit in ipairs(PARTY_UNITS) do
  local frame = CreateFrame("Frame")
  if pcall(frame.RegisterUnitEvent, frame, "UNIT_SPELLCAST_SUCCEEDED", unit) then
    frame:SetScript("OnEvent", function(_, _, _, _, spellID)
      Safe(OnPartyCast, unit, spellID)
    end)
  else
    Log("could not register party casts for %s", unit)
  end
end

-- Slash command ---------------------------------------------------------------------

local HELP = {
  "/smp send - send a test message on every channel now",
  "/smp bnet - show the Battle.net link to each party member",
  "/smp secrecy - list which spells the game never hides",
  "/smp flags - check Blizzard's yes/no flags of every spell (out of combat, then /reload)",
  "/smp flags clear - drop the saved flag results",
  "/smp meter - check the damage meter now; /smp meter on - switch it on",
  "/smp sounds - register the defensive sounds again",
  "/smp status - chat lock, boss, peers and the last boss summary",
  "/smp results - send your last boss results to the other probe users again",
  "/smp show | hide - the panel",
  "/smp verbose - print every log line in chat (again to stop)",
  "/smp clear - empty the log",
}

local function PrintLinks()
  RefreshParty("command")
  local any = false
  for _, unit in ipairs(PARTY_UNITS) do
    local full = partyNames[unit]
    if full then
      any = true
      local id = partyGUIDs[unit] and links[partyGUIDs[unit]]
      Say("%s: %s", full, id and ("Battle.net game account " .. Show(id))
        or "no Battle.net link (you need to be Battle.net friends)")
    end
  end
  if not any then
    Say("not in a party, or out of combat reads failed")
  end
end

local function PrintStatus()
  Say("%s", StatusText())
  for _, peer in pairs(peers) do
    Say("probe user %s, last message %.0f s ago", peer.name, GetTime() - peer.lastSeen)
  end
  Say("last boss: %s", SummaryText("boss") or "none yet")
end

SLASH_SAKAMINDPROBE1 = "/smp"
SlashCmdList.SAKAMINDPROBE = function(message)
  local command, argument = strsplit(" ", strtrim((message or ""):lower()), 2)
  Safe(function()
    if command == "send" then
      SendRound("manual")
      Say("sent; /smp status or the log shows the results")
    elseif command == "bnet" then
      PrintLinks()
    elseif command == "secrecy" then
      SecrecyReport()
    elseif command == "flags" then
      if argument == "clear" then
        db.flags = nil
        Say("flag results dropped")
      else
        StartFlags()
      end
    elseif command == "meter" then
      if argument == "on" then
        if InCombatLockdown() then
          Say("switch the damage meter on out of combat")
        else
          SetCVar("damageMeterEnabled", "1")
          Say("damage meter switched on (damageMeterEnabled = %s)", Show(GetCVar("damageMeterEnabled")))
        end
      else
        CheckAllMeters("command")
        for _, unit in ipairs(PARTY_UNITS) do
          if meterStatus[unit] then
            Say("%s: %s", partyNames[unit] or unit, meterStatus[unit])
          end
        end
      end
    elseif command == "sounds" then
      RegisterSounds("command")
      Say("%d sounds registered (see the log for refusals)", #soundIDs)
    elseif command == "status" then
      PrintStatus()
    elseif command == "results" then
      if Locked() then
        Say("wait until the chat lock ends")
      elseif SendResults("command") then
        Say("boss results sent to the other probe users")
      else
        Say("not sent: no boss results yet, or no other probe user in the group")
      end
    elseif command == "show" then
      BuildPanel()
      SetPanelShown(true)
    elseif command == "hide" then
      SetPanelShown(false)
    elseif command == "verbose" then
      db.verbose = not db.verbose
      Say("verbose %s", db.verbose and "on" or "off")
    elseif command == "clear" then
      wipe(db.log)
      Say("log cleared")
    else
      for _, line in ipairs(HELP) do
        print(line)
      end
    end
  end)
end
