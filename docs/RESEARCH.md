# Sharing defensive cooldowns during boss fights: research

Research, 2026-11-10. The question: how can SakaMind tell the core party
(paladin, druid and the player's priest) about each other's defensive
cooldowns *during* boss fights, when the game locks add-on chat?

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
- **Test**: needs the in-game test run ([TEST-RUN.md](TEST-RUN.md)).

## Short answer

- Blizzard's rule: add-ons may not communicate with other players while an
  instance encounter is in progress (or a keystone run or PvP match), and
  Blizzard closes workarounds as people find them. **Verified.**
- What works within that rule:
  - Syncing up to the pull and after the kill or wipe. The moment the lock
    starts still counts: a restriction marked `Activating` isn't enforced
    until the event has been handled. **Verified (docs); Test.**
  - Timers already running at the pull keep running through the fight.
  - Showing, live, every defensive that puts a buff on a friendly unit:
    Blizzard always lets add-ons pick out group members' helpful buffs by
    spell ID, in combat too. **Verified.**
  - Perhaps a sound when such a buff lands (`C_UnitAuras.AddAuraSound`).
    **Test.**
- The gap: uses during the fight that leave no buff, above all Lay on Hands
  (the player's main concern, 2026-11-10), and a new countdown for any use
  made during the fight.
- Routes for the gap, all **Test**:
  1. Battle.net game data (`C_BattleNet.SendGameData`): not marked as
     restricted in the source, never tested in public, skipped by DBM during
     the lock. The player chose to test it (decision below).
  2. Blizzard's damage meter: it records Lay on Hands and Tranquility as
     heals. Readable after combat; in combat at best shown as icons.
  3. Never-hidden auras: if Forever never hides some defensive buff, or
     Forbearance, an add-on can read it in combat and time the use.
- Ruled out: overlays that read the combat log file, side channels in the
  game, and anything that feeds data back into the game from outside.
- Account risk: no first-hand report was found of a suspension caused by an
  add-on that works around the Midnight restrictions. Blizzard's record is to
  break the API, and to ban for outside tools (§9).

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
  Whether it accepts helpful auras on party members: **Test.**

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
  Lay on Hands at once. Getting that out during the boss needs route 1,
  Battle.net. **Test.**
- Forbearance (25771) exists on Forever. Which spells apply it, and whether
  it's never hidden: **Test** (the probe shows it if it is).

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

1. **Sync at the edges, plus the live buff display.** Works within the
   rules. Covers what was ready at the pull, running timers, and each
   buff-giving defensive as it happens. Misses Lay on Hands and Rebirth
   during the fight, and new countdowns.
2. **Battle.net game data during boss fights.** Live updates for
   everything, Lay on Hands included, if the lock doesn't cover it. Only
   between Battle.net friends; may be closed later.
3. **The damage meter for Lay on Hands.** After the fight for sure; during
   it only if icons can be shown.

Ruled out: combat log overlays (EULA 1-C, delayed writes), side channels in
the game (hidden during the lock), and external tools feeding input back
into the game (automation).

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
