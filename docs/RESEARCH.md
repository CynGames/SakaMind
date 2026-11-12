# Sharing defensive cooldowns during boss fights: research

Research, 2026-11-10. The question: how can SakaMind tell the core party
(paladin, druid and the player's priest) about each other's defensive
cooldowns *during* boss fights, when the game locks add-on chat?

Status: SakaMind was dropped on 2026-11-11 after the tests recorded here
(see "Outcome" under the options). This file is the record of what they
found.

This continues the research done for Cynbrew, which lives in the Cynbrew
repo (`docs/PARTY-COOLDOWNS-RESEARCH.md`). It covers party cooldowns outside
boss fights: party members' casts are hidden, their buffs are hidden in
combat, and each client can report its own cooldowns over add-on messages.
Cynbrew dropped the feature because the others would have needed all of
Cynbrew; SakaMind is the small add-on the core party installs instead.

Confidence labels:

- **Verified**: read in Blizzard's UI source for this client
  (Gethe/wow-ui-source, branch `forever`, commit `9dc84f0`, = 1.60.1 70862),
  in the add-ons installed on this client, or on the cited page.
- **Reported**: found by web research and not re-read here.
- **In game**: seen in the probe's log on the player's client.
- **Test**: needs the in-game test run ([TEST-RUN.md](TEST-RUN.md)).

## Short answer

- Blizzard's rule: add-ons may not communicate with other players while an
  instance encounter is in progress (or a keystone run or PvP match), and
  Blizzard closes workarounds as people find them. **Verified.**
- What works within that rule:
  - Syncing up to the pull and after the kill or wipe. A restriction
    marked `Activating` isn't enforced until the event has been handled
    (**Verified**, docs), but messages sent then never arrived (test run
    1), so the last sync has to come before the pull.
  - Timers already running at the pull keep running through the fight.
  - Showing, live, every defensive that puts a buff on a friendly unit:
    Blizzard always lets add-ons pick out group members' helpful buffs by
    spell ID, in combat too. **Verified.**
  - Perhaps a sound when such a buff lands (`C_UnitAuras.AddAuraSound`).
    **Test.**
- The gap: uses during the fight that leave no buff, above all Lay on Hands
  (the player's main concern, 2026-11-10), and a new countdown for any use
  made during the fight.
- Routes for the gap, tested in test run 1:
  1. Battle.net game data (`C_BattleNet.SendGameData`): not marked as
     restricted in the source, never tested in public, skipped by DBM during
     the lock. The player chose to test it (decision below). Result: it
     returns `AddOnMessageLockdown` during boss encounters like party
     messages. **In game.**
  2. Blizzard's damage meter: it records Lay on Hands and Tranquility as
     heals. Readable after combat; in combat at best shown as icons.
     Result: in combat only the number of spells, IDs hidden; Lay on Hands
     by ID after combat. **In game.**
  3. Never-hidden auras: if Forever never hides some defensive buff, or
     Forbearance, an add-on can read it in combat and time the use.
     Result: none is never hidden. **In game.**
- Ruled out: overlays that read the combat log file, side channels in the
  game, and anything that feeds data back into the game from outside.
- Account risk: no first-hand report was found of a suspension caused by an
  add-on that works around the Midnight restrictions. Blizzard's record is to
  break the API, and to ban for outside tools (§9).
- Test run 1 settled the routes (next section): Battle.net is locked like
  everything else, a send at the pull never arrives, and own casts are
  readable throughout, so each client can report its own uses outside boss
  encounters at once and right after the boss for uses during it.
- A key press doesn't lift the lock: sends made from a key press during two
  boss encounters were locked like the timer sends (next sections), so no
  key bind, SakaBind's included, can send during a boss. **In game.**
- Party members' casts barely reach add-ons while the player is in combat
  (party-cast test), so no display can follow them mid-fight. **In game.**
- Open lead: the damage meter, which lists a party member's Lay on Hands
  live with its spell ID hidden. Blizzard accepts hidden spell IDs in its
  yes/no spell checks, in `SetAlphaFromBoolean` and in status bars, so a
  light could show only when the paladin's healing list holds Lay on Hands:
  live, but without the time of use (§5). **Test.**

## Test run 1 (2026-11-10)

A real dungeon with two bosses (kills after 42 s and 52 s) and three
clients running the probe: the player's priest, the paladin and the druid,
all Battle.net friends. Everything below is from the player's log, which
also holds the other two clients' results. **In game.**

- During both bosses every send failed with `AddOnMessageLockdown`: party,
  whisper and Battle.net game data alike, on all three clients, and nothing
  arrived. **Battle.net is no way around the lock.**
- At the pull the chat restriction went `Activating`. Sends made then
  returned `Success` but never arrived, so a last snapshot at the pull
  doesn't work; the last sync has to come before it.
- The lock ended together with the encounter. Messages sent at that moment
  and after the kill arrived within a second.
- Outside boss encounters messages work in combat too: party, whisper (to
  the sender name from messages) and Battle.net all arrived during trash
  fights.
- Own casts: every cast on each client had a readable spell ID, in trash
  combat and during the bosses (the player 18 casts during a boss, the
  other two 17 to 33 per boss; none hidden). Each client knows its own
  defensives the moment it uses them, Lay on Hands included.
- Damage meter: in combat it gives how many healing spells each party
  member has used, with their IDs hidden. After combat the IDs are
  readable: the paladin's Lay on Hands (rank 2800) showed up after two
  trash fights. No defensive was used during the two bosses.
- Seen and heard by the player:
  - The paladin's Lay on Hands icon appeared in the panel's healing row
    during the trash fight. The meter's hidden spell IDs can be drawn as
    icons live. Add-ons still can't tell which spell it is: every field
    naming a spell is secret in combat and there is no per-spell query
    (`DamageMeterDocumentation.lua`), so the icon is a display, not a
    trigger for sounds or timers.
  - Dings played when big defensives landed on party members, so aura
    sounds work for helpful auras on party units.
  - Whether the panel showed defensive buffs wasn't noticed. Cynbrew's
    frames use the same aura containers in combat, so it very likely
    works. **Test** at the next run.

What this means for SakaMind:

- Share each defensive the moment it's used whenever no boss encounter is
  on, in combat too; and share cooldown state on every change, since
  nothing sent at the pull arrives.
- During a boss nothing goes out. Each client keeps its own uses and sends
  them when the encounter ends, so the others learn of a Lay on Hands used
  mid-fight within a second of the kill or wipe. Countdowns known before
  the pull keep running on each client.
- Leave Battle.net game data out: it adds nothing over party messages.
- Live during a boss, without messages: helpful buffs on the panel, a ding
  when a big defensive lands, and each member's healing spells as icons
  from the damage meter, where a Lay on Hands shows the moment it's used.

## Key-press test (2026-11-11)

In a group without other probe users, the player pressed `/smp send` during
two boss encounters, 7 s and 37 s in. **In game.**

- Both sends returned `AddOnMessageLockdown`, on the party channel and on
  all four whispers, like the timer sends in test run 1. A key press
  doesn't lift the lock, so sending from SakaBind's key presses wouldn't
  help.
- Battle.net game data wasn't part of it: nobody in the group was a
  Battle.net friend. From timer sends it returned the same result in test
  run 1.
- As in test run 1, the lock started at each pull and ended with each of
  the six encounters (32 s to 109 s).

## Party-cast test (2026-11-11)

A group with the paladin, the druid and others; about 70 trash fights, no
boss in the saved log. Only the player ran the new probe. It counted party
members' casts and tried display calls with each hidden spell ID. **In
game.**

- While the player was in combat, party casts almost never reached
  add-ons: 21 in all, none in 57 of the fights and at most 7 in one, while
  the player cast 667 spells (up to 103 in one fight). The paladin's Lay on
  Hands around 19:44 (the damage meter listed it) didn't arrive; nothing
  from any party member did in that 2½-minute fight.
- Out of combat they arrive: 30 in one stretch, 26 of them the paladin's,
  all with the spell ID hidden.
- Every call tried with a hidden spell ID was accepted in combat:
  `C_Spell.IsSpellImportant`, `C_UnitAuras.AuraIsBigDefensive`,
  `C_Spell.IsSpellHelpful`, `SetAlphaFromBoolean` with the answer,
  `StatusBar:SetValue` with the ID, `C_Spell.GetSpellInfo`, and `SetAlpha`
  with its cast time. Only `curve:Evaluate` refused, as documented.
- So no display can follow a party member's casts during a fight, but the
  display calls work with hidden spell IDs. The damage meter is the source
  that sees Lay on Hands live.

## Findings

### 1. The rule and the lock

- Blizzard's Midnight API notes, October 1 (Midnight public alpha): "addons
  are not allowed to send communications to other players (either through
  addon comms or regular chat)". October 11: relaxed to apply only while "A
  mythic keystone run has started and not yet completed.", "A PvP match has
  started and not yet completed." or "An instance encounter is in
  progress." **Verified** ([notes][w-1200]).
- On this client the lock is the `Chat` restriction ("The player is in a
  state where addon chat communications are restricted"), read with
  `C_ChatInfo.InChatMessagingLockdown()`. `SendAddonMessage` then returns
  `AddOnMessageLockdown` (11). **Verified** ([restriction types][b-restr-types],
  [send results][b-chat-result]).
- In Shadowfang Keep the lock ran from each boss pull to the kill and never
  on trash (Cynbrew's restriction log, 2026-11-07). **Verified.**
- `ADDON_RESTRICTION_STATE_CHANGED` "will always be fired before a
  restriction becomes active, or after it is deactivated". `Activating` is
  the state "used during the dispatch of ADDON_RESTRICTION_STATE_CHANGED to
  infer that a restriction is about to become active, but won't be enforced
  until event dispatch has completed." So a last message can go out at the
  pull. **Verified** ([event][b-restr-event], [states][b-restr-states]);
  the probe sends one then.
- Blizzard on workarounds: "wanting to avoid a frustrating cat-and-mouse
  situation with addon authors pointing out loopholes in our logic"
  ([Combat Philosophy][s-blizz], 2025-11-13), and in the January 21 notes:
  "We have addressed a whole host of addon communication workarounds"
  (AFK/DND, Battle.net AFK/DND, group finder, club notes, voice channel
  members, calendar...). **Verified (heading and summary); the full list is
  Reported.**

### 2. What else is hidden during the lock

- Tagged `SecretInChatMessagingLockdown` ("when encounter, challenge mode,
  or PvP match addon restrictions are in effect, and when the player is on
  a communication-restricted map such as a dungeon or raid",
  [predicate][b-pred-chat]): party, instance, whisper and Battle.net whisper
  chat events; Communities messages and members; `IsRaidMarkerActive` and
  `GetNextAvailableRaidTargetMarkerIndex`; `UnitIsAFK` and `UnitIsDND`;
  `READY_CHECK`; player countdowns; `GUILD_MOTD`; group finder listings;
  calendar invites; voice chat members, speaking state and speech-to-text
  messages. `GetRaidTargetIndex` is always secret. **Verified.**
- Not tagged: `CHAT_MSG_ADDON`, `CHAT_MSG_ADDON_LOGGED` and
  `BN_CHAT_MSG_ADDON`. What arrives can be read; the block is on sending.
  **Verified.**
- Macros: `SendChatMessage` and `C_BattleNet.SendWhisper` carry
  `RestrictedForMacroChatMessages`: "Restricts sending chat messages on
  chat types that can be observed by external players. Only applies during
  instance encounters for messages initiated from macros." Party chat from a
  macro still goes out, but add-ons receive it as secret during the lock and
  in dungeons. Useful only for humans to read. **Verified**
  ([precondition][b-macro-chat]).
- Pings don't load on Forever: `Blizzard_PingUI.toc` has
  `AllowLoadGameType: mainline`, and Forever's game type is `camelot`.
  **Verified** ([toc][b-ping]).

### 3. Battle.net game data

- `C_BattleNet.SendGameData(gameAccountID, prefix, data)` has no
  `HasRestrictions` flag and returns `SendAddonMessageResult`, the same
  results as add-on messages, the lock included. **Verified**
  ([docs][b-bnet-send]).
- `BN_CHAT_MSG_ADDON` (prefix, text, channel, senderID) isn't secret.
  **Verified.**
- `C_BattleNet.GetGameAccountInfoByGUID(guid)` maps a party member to their
  game account (`gameAccountID`, `characterName`, `playerGuid`...). Only
  Battle.net friends have one. **Verified.**
- DBM uses Battle.net game data on this client for world-buff syncs, and
  skips that send while the chat lock is on
  (`DBM-Core\modules\AddonComms.lua:151`). **Verified.**
- Nobody has published a test of sending it during an encounter. Blizzard
  has closed nearby routes: `BNSetAFK` and `BNSetDND` during the lock
  (January 2026), Battle.net whispers from macros during encounters
  (12.0.1), chat channel APIs during the lock (12.0.5). **Reported.**
- **Decision, 2026-11-10:** test it. The player's view: if Blizzard blocks
  it later, that route stops working and SakaMind keeps the rest.

### 4. The combat log file

- Blizzard (Kaivax, 2023-08-21) on overlays drawn from the combat log: "We
  intend to make changes to how the Advanced Combat Log is populated, in
  advance of Dragonflight Season 3, that will prevent its use in this
  way", pointing to EULA section 1-C on "third-party applications that
  modify or facilitate gameplay". **Verified** ([post][s-kaivax]).
- Wowhead, 2023-11-06: "Combat Log Changes with Patch 10.2 - Measures to
  Prevent Out of Game Overlays" ([article][s-wh-log]). Reported details: the
  game keeps the log in memory and writes it to the file once combat ends;
  a 2025 forum report describes delays of several minutes. **Headline
  verified; details Reported.**
- Ruled out. No combat log file has been written on this PC either
  (`_forever_\Logs`, 2026-11-10).

### 5. What shows during a boss without any message

- Aura containers: "Filtering helpful spells on the active player / any
  group members (or their pets) is always allowed." Harmful auras on
  friendly units can't be filtered by spell ID unless the spell is never
  secret, so that "Move now!"-style displays of boss debuffs stay
  impossible. **Verified** ([source][b-ac-gate]).
- Aura buttons forbid untrusted scripts, layout scripts, scripted input and
  reparenting ([source][b-ac-button]). An add-on can't notice when one
  appears or keep a mark after it goes away. **Verified.**
- `C_UnitAuras.AddAuraSound(trigger, {unitToken, spellID, soundFileID,
  throttleSeconds...})` plays a sound when a spell's aura is added, stacks
  or is removed on a unit. It replaced `AddPrivateAuraAppliedSound` in
  12.1.0. DBM registers its sounds only outside the chat lock ("adding
  sounds still combat restricted", `DBM-Core\modules\objects\BossMod.lua`).
  Registering sounds for helpful auras on you and party1 to party4 works
  out of combat: 65 sounds, none refused (**In game**, 2026-11-10). Whether
  they play: **Test.**
- Party members' casts (`UNIT_SPELLCAST_SUCCEEDED`) come with their spell
  ID secret (`SecretWhenUnitSpellCastRestricted`), and while the player is
  in combat they almost never come at all. **In game** (party-cast test).
- The secret ID can't become a countdown by itself: duration objects and
  the Cooldown widget's setters take secret values only from Blizzard's own
  code (`AllowedWhenUntainted`), there is no lookup of a spell's base
  cooldown, and curves (`LuaCurveObject:Evaluate`) take secret values only
  from Blizzard's code too. **Verified** (docs).
- But a secret can decide what is visible. `SetAlphaFromBoolean` takes a
  secret boolean from add-on code, and these checks take a secret spell ID
  from add-on code and return a boolean: `C_Spell.IsSpellImportant`,
  `C_Spell.IsSpellHelpful`, `C_Spell.IsSpellHarmful`,
  `C_Spell.SpellHasRange` and `C_UnitAuras.AuraIsBigDefensive` (all
  `AllowedWhenTainted`). Nested frames multiply their alpha, and swapping
  the two alpha values inverts a check, so checks combine.
  `StatusBar:SetValue` takes a secret number as well: a bar whose range is
  one ID wide fills only from that ID up, so a revealing bar and a
  covering bar together could show something for one exact spell ID, with
  no checks needed. **Verified** (docs), and accepted in combat
  (party-cast test). How the bars draw it: **Test.**
- Fed the damage meter's secret spell IDs, such a display could show a
  Lay on Hands light only when the paladin's healing list holds Lay on
  Hands. The list only says the spell was used this fight, not when, so the
  light has no countdown. Whether the checks single out Lay on Hands among
  the paladin's heals: **Test** (`/smp flags`).
- `C_Secrets` reports every spell the probe watches as hidden in combat,
  both aura and cast, Lay on Hands and Forbearance included; none is never
  hidden. So no defensive can be timed live from its aura or cast ID.
  **In game** (2026-11-10).

### 6. Lay on Hands

- On Forever: ranks 633, 2800 and 10310 (9257 and 17233 are other versions).
  It heals and restores mana; it puts no buff on the target. Forever has no
  Improved Lay on Hands (no such name in the client's spell table, build
  70862). **Verified.**
- Blizzard's damage meter: `C_DamageMeter.GetCombatSessionSourceFromType`
  (`Current`, `HealingDone`, the member's GUID) returns per-spell rows
  (`spellID`, `totalAmount`...). It is `SecretWhenInCombat`. After combat
  the rows are readable, so SakaMind can tell that Lay on Hands was used in
  the last fight, but not when. In combat the probe checks whether the rows
  can at least be shown as icons (secret spell IDs may be passed to
  `C_Spell.GetSpellTexture`). **Verified (docs); Test.**
- On Forever the meter is switched on with the `damageMeterEnabled` setting
  (its checkbox in the options is retail-only; Edit Mode shows the window).
  **Verified (source).**
- The paladin's own client sees its own casts (casts are secret for every
  unit except you and your pet, Cynbrew research §6), so it knows about a
  Lay on Hands at once. Nothing can send it out during the boss: party,
  whisper and Battle.net are all locked, from a key press too (test run 1,
  key-press test).
- Forbearance (25771) exists on Forever and is hidden in combat like the
  rest (**In game**). Which spells apply it: **Test**.

### 7. Other add-ons

- MiniCC (now MiniAuras) removed its friendly and enemy cooldown trackers on
  2026-08-12, "which 12.1 cannot support". **Verified**
  ([commit][s-miniauras]).
- LibOpenRaid stopped its comms in combat (2026-01-20); Northern Sky Raid
  Tools checks cooldowns at the ready check; InterruptTrack syncs only
  outside keystones; BigWigs drops sends that return 11. **Reported.**

### 8. Add-on messages on Forever

- Party and whisper add-on messages work outside the lock (two-account
  test, 2026-09-29). Custom chat channels return success but never deliver
  (same test; Blizzard forum report, 2026-11-06). Trial and Veteran
  accounts can't send add-on messages on Forever 1.60.1. **Reported**
  ([test][s-reddit], [forum][s-forum], [wiki][s-wiki-send]).
- Party add-on messages: the probe's sends return `Success` and come back
  to the sender, as they should. **In game** (2026-11-10).
- Names differ between messages and units. Add-on messages give the sender
  as `Name Realm-<internal realm name>`, while `UnitFullName` gives `Name`
  and `Realm`, so matching players by name fails. The probe puts the
  sender's GUID in every message (protocol 2) and identifies players by
  it. Whether whispers to the message-form name arrive: **Test.** Names:
  **In game** (2026-11-10).
- `C_ChatInfo.AreOutgoingAddonChatMessagesRestricted()` returns true on
  Forever's realms. Its documentation says it covers add-ons sending chat
  messages, not add-on messages ("the ability for addons to receive comms
  is controlled separately"). **Verified** (docs) and **In game**.

### 9. Account risk of workaround add-ons

Checked 2026-11-10: r/wow, r/wowaddons, r/WowUI, r/wowforever and
r/classicwow over the past year, Blizzard's forums and news sites.

- No first-hand report was found of an account suspension caused by an
  add-on that works around the Midnight restrictions. **Reported
  (searches).**
- A developer asked in March 2026 whether add-ons that track interrupts and
  group cooldowns around the restrictions could get them punished. Nobody
  reported a ban; replies expected Blizzard to patch such holes, and to ban
  only for things like Lua unlockers ([thread][r-workarounds]).
  **Community.**
- Top raid guilds used workaround add-ons on stream in the March 2026 race
  to world first, timers for other raid members included. Liquid said
  Blizzard knew what they had built and how ([thread][r-liquid]); "Blizzard
  took no action against them" ([Inven Global, 2026-04-01][s-inven]).
  **Community, Secondary.**
- First-hand bans that players blamed on add-ons were unconfirmed or
  overturned: a Classic Era player banned while working on add-ons,
  overturned the next day ([forum, 2026-07-12][f-dev-ban]); WoW Forever
  launch-week "Cheat Programs (Hacks)" bans, which some blamed on RestedXP,
  with false positives rescinded on 2026-11-07 ([thread][r-rescinded]).
  **Community.**
- Where account action does happen: outside programs (Lua unlockers,
  automation, multiboxing helpers), gold buying, names. The game director:
  players who use third-party tools or modify the client to get around the
  rules face account action ([PC Gamer, 2025-10-01][s-pcg]; paywalled, quoted
  from search summaries). One add-on case: on Chinese Classic realms,
  player-rating add-ons such as Archon Tooltip were forbidden from
  2026-07-20, with account suspension for continued use
  ([PC Games, 2026-07-17][s-cn]). **Secondary.**
- For SakaMind: an in-game add-on on a public API, Battle.net game data
  included, sits where the record shows Blizzard breaking the API rather
  than banning players. No Blizzard statement promises that. Keep SakaMind
  free (paid add-ons break Blizzard's add-on policy) and never pair it with
  outside tools.

## Options, ranked

After test run 1:

1. **Each client reports its own uses, plus the live buff display.** At
   once outside boss encounters (in combat too), and right after the
   encounter for uses during it. Works within the rules. Misses only the
   live moment of a use without a buff (Lay on Hands, Rebirth) during a
   boss.
2. **The damage meter for Lay on Hands.** Live as an icon among the
   paladin's heals (test run 1), by ID after combat. With Blizzard's yes/no
   checks or status bars, perhaps a light that shows only for Lay on Hands
   (§5, **Test**). It says the spell was used this fight, not when. Also
   covers party members who don't run SakaMind.
3. ~~A countdown revealed on each party cast.~~ Party casts barely reach
   add-ons during the player's combat (party-cast test).
4. ~~Battle.net game data during boss fights.~~ Locked like party
   messages (test run 1).
5. ~~Sending from a key press (SakaBind).~~ Locked like the timer sends
   (key-press test).

Ruled out: combat log overlays (EULA 1-C, delayed writes), side channels in
the game (hidden during the lock), and external tools feeding input back
into the game (automation). Rejected by the player: steps that need
someone's attention mid-fight, such as a pre-filled chat line to send or
clicking to start a countdown.

Outcome, 2026-11-11: the player dropped SakaMind instead of testing
option 2's light. The probe's solo flag check (`/smp flags`), meant to show
whether Blizzard's yes/no checks can single out Lay on Hands, was never run.

## Spell IDs on Forever

From the client's spell table (build 70862) and Cynbrew's research table.
Cooldowns marked "?" weren't checked; SakaMind reads them out of combat.

| Class | Spell | IDs | Buff on a friend | Cooldown |
|---|---|---|---|---|
| Paladin | Divine Shield | 642, 1020 | yes, self | 300 s |
| Paladin | Divine Protection | 498, 5573 | yes, self | ? |
| Paladin | Blessing of Protection | 1022, 5599, 10278 | yes, target | 300 s |
| Paladin | Blessing of Sacrifice | 6940, 20729 | yes, target | ? |
| Paladin | Divine Intervention | cast 19752, buff 19753 | yes, target | 3600 s |
| Paladin | Lay on Hands | 633, 2800, 10310 | no | 1200 s |
| Paladin | Forbearance (debuff) | 25771 | debuff | - |
| Druid | Barkskin | 22812 | yes, self | ? |
| Druid | Innervate | 29166 | yes, target | 360 s |
| Druid | Tranquility | 740, 8918, 9862, 9863 | yes, party in range | 300 s |
| Druid | Rebirth | 20484, 20739, 20742, 20747, 20748 | no | 1800 s |
| Druid | Nature's Swiftness | 17116 | yes, self | 180 s |
| Druid | Frenzied Regeneration | 22842 | yes, self | ? |
| Priest | Power Infusion | 10060 | yes, target | 180 s |
| Priest | Pain Suppression | 402004 | yes, target | 180 s |
| Priest | Fear Ward | 6346 | yes, target | 180 s |

## Sources

- **Blizzard UI source (primary).** Gethe/wow-ui-source, branch `forever`,
  commit `9dc84f0d3bbae1768ac3405b3716000bd93eda06` = 1.60.1 (70862).
- **Installed add-ons (read only).** `C:\Program Files (x86)\World of
  Warcraft\_forever_\Interface\AddOns\`: DBM-Core (AddonComms.lua,
  BossMod.lua).
- **Spell table.** wago.tools SpellName export for build 1.60.1.70862.
- **Blizzard statements.** API change notes for 12.0.0 ([warcraft.wiki.gg
  copy][w-1200]); [Combat Philosophy and Addon Disarmament in
  Midnight][s-blizz]; [Kaivax on combat log overlays][s-kaivax].
- **Other.** [Wowhead on the 10.2 combat log changes][s-wh-log];
  [MiniAuras commit][s-miniauras]; [two-account test][s-reddit];
  [forum bug report][s-forum]; [wiki: SendAddonMessage][s-wiki-send].

[b-restr-types]: https://github.com/Gethe/wow-ui-source/blob/9dc84f0d3bbae1768ac3405b3716000bd93eda06/Interface/AddOns/Blizzard_APIDocumentationGenerated/RestrictedActionsConstantsDocumentation.lua#L19-L33
[b-restr-states]: https://github.com/Gethe/wow-ui-source/blob/9dc84f0d3bbae1768ac3405b3716000bd93eda06/Interface/AddOns/Blizzard_APIDocumentationGenerated/RestrictedActionsConstantsDocumentation.lua#L13-L15
[b-restr-event]: https://github.com/Gethe/wow-ui-source/blob/9dc84f0d3bbae1768ac3405b3716000bd93eda06/Interface/AddOns/Blizzard_APIDocumentationGenerated/RestrictedActionsDocumentation.lua#L97-L107
[b-chat-result]: https://github.com/Gethe/wow-ui-source/blob/9dc84f0d3bbae1768ac3405b3716000bd93eda06/Interface/AddOns/Blizzard_APIDocumentationGenerated/ChatConstantsDocumentation.lua#L147-L168
[b-pred-chat]: https://github.com/Gethe/wow-ui-source/blob/9dc84f0d3bbae1768ac3405b3716000bd93eda06/Interface/AddOns/Blizzard_APIDocumentationGenerated/SecretPredicatesDocumentation.lua#L65-L68
[b-macro-chat]: https://github.com/Gethe/wow-ui-source/blob/9dc84f0d3bbae1768ac3405b3716000bd93eda06/Interface/AddOns/Blizzard_APIDocumentationGenerated/ChatConstantsDocumentation.lua#L237-L240
[b-ping]: https://github.com/Gethe/wow-ui-source/blob/9dc84f0d3bbae1768ac3405b3716000bd93eda06/Interface/AddOns/Blizzard_PingUI/Blizzard_PingUI.toc
[b-bnet-send]: https://github.com/Gethe/wow-ui-source/blob/9dc84f0d3bbae1768ac3405b3716000bd93eda06/Interface/AddOns/Blizzard_APIDocumentationGenerated/BattleNetDocumentation.lua#L319-L334
[b-ac-gate]: https://github.com/Gethe/wow-ui-source/blob/9dc84f0d3bbae1768ac3405b3716000bd93eda06/Interface/AddOns/Blizzard_AuraContainer/Blizzard_AuraContainerUtil.lua#L52-L80
[b-ac-button]: https://github.com/Gethe/wow-ui-source/blob/9dc84f0d3bbae1768ac3405b3716000bd93eda06/Interface/AddOns/Blizzard_AuraContainer/Blizzard_AuraButton.xml#L16-L24
[w-1200]: https://warcraft.wiki.gg/wiki/Patch_12.0.0/API_changes/notes
[s-blizz]: https://news.blizzard.com/en-us/article/24246290/combat-philosophy-and-addon-disarmament-in-midnight
[s-kaivax]: https://us.forums.blizzard.com/en/wow/t/nerfing-combat-logs-will-it-happen-should-it-happen/1654695/11
[s-wh-log]: https://www.wowhead.com/news/combat-log-changes-with-patch-10-2-measures-to-prevent-out-of-game-overlays-335813
[s-miniauras]: https://github.com/Verubato/mini-auras/commit/152f0622ec616b6dfe8dfb7d253fd621677e5be3
[s-reddit]: https://www.reddit.com/r/wowaddons/comments/1wta39c/
[s-forum]: https://us.forums.blizzard.com/en/wow/t/add-on-messages-are-blocked-in-chat-channels/2403369
[s-wiki-send]: https://warcraft.wiki.gg/wiki/API_C_ChatInfo.SendAddonMessage
[r-workarounds]: https://www.reddit.com/r/wowaddons/comments/1s4omrb/can_you_get_in_trouble_for_workarounds_on_api/
[r-liquid]: https://www.reddit.com/r/wow/comments/1rwi2pf/it_seems_that_liquid_has_found_a_way_around_addon/
[s-inven]: https://www.invenglobal.com/articles/20392/world-of-warcraft-midnight-addon-restrictions-fail-as-top-rwf-guilds-keep-using-raid-addons
[f-dev-ban]: https://us.forums.blizzard.com/en/wow/t/hackscheats-permaban-while-developing-addons/2326159
[r-rescinded]: https://www.reddit.com/r/wowforever/comments/1xq5t1o/false_positive_bans_were_rescinded/
[s-pcg]: https://www.pcgamer.com/games/world-of-warcraft/as-world-of-warcraft-winds-down-its-combat-addon-support-director-ion-hazzikostas-is-all-composure-about-rule-breakers-because-frankly-this-is-far-from-the-first-time
[s-cn]: https://www.pcgames.de/World-of-Warcraft-Spiel-42971/News/Toxische-Addons-verboten-1548626/
