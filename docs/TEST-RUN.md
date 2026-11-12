# Test run: SakaMind Probe

One dungeon with at least one boss settles what SakaMind's design depends on
(see [RESEARCH.md](RESEARCH.md)). Players: you (priest) and the paladin; the
druid too if they can. The probe does its tests by itself; you mostly play.

## Before the run

1. Install the probe.
   - You: it's linked into the game's add-on folder already (junction
     `_forever_\Interface\AddOns\SakaMindProbe`). Don't install SakaMind
     from CurseForge on your PC: the app would write into the linked
     folder, which is the repository.
   - The paladin: install "SakaMind" with the CurseForge app, on their WoW
     Forever installation; later versions then come as updates. Until the
     CurseForge project is live, download the zip from the GitHub release
     instead and extract it into `World of Warcraft\_forever_\Interface\AddOns\`,
     so that a folder `SakaMindProbe` sits next to their other add-ons.
   - Both: restart the game fully (a new add-on isn't picked up by
     `/reload`) and make sure "SakaMind Probe" is enabled in the add-on list.
2. Be Battle.net friends with the paladin (BattleTag). The Battle.net test
   needs it.
3. Both: type `/smp meter on` once, to switch Blizzard's damage meter on.
4. Group up. In town, both:
   - `/smp status`: should say "probe users in group 1" or more. The probes
     find each other a few seconds after grouping, and they test only
     between probe users.
   - `/smp bnet`: should show the other player's Battle.net game account.
   - `/smp send`, then `/smp status`: should list the other player as a
     "probe user" with a recent message.
5. The panel shows each party member in a row: their defensive buffs right
   now, Forbearance, and their healing this fight from the damage meter.
   Drag it wherever it doesn't get in the way, or close it with its `x`
   button (`/smp show` brings it back). It can't be closed or opened
   during combat.

## In the dungeon

6. Trash: just play. The probe sends test messages by itself.
7. Boss: at the pull the probe says how many probe users it sends to,
   every 8 seconds. If it says there are none, nothing gets tested; check
   step 4 before the next boss. During the fight, please:
   - Paladin: Blessing of Protection on someone (you, ideally), Divine Shield
     if it's safe, and Lay on Hands on someone who's hurt.
   - Druid, if present: Barkskin and Innervate.
   - You: Power Infusion or Fear Ward on the paladin.
8. While it happens, watch for:
   - the buff showing in the paladin's (or its target's) row on the panel;
   - a "ding" when a defensive lands;
   - a Lay on Hands icon in the paladin's healing row;
   - green chat lines: "received a BNET (or PARTY, WHISPER) message during
     the boss", "damage meter shows Lay on Hands", "your ... cast was
     readable".
9. About 15 seconds after the kill, the probe prints a "boss summary" line:
   what was sent on each channel, what came back, and what arrived. Then
   each probe sends its own results to the other, and you get a chat line
   "got <name>'s results for the last boss". If it doesn't come,
   `/smp results` on the paladin's side sends them again.
10. A second boss, if you can, makes the result surer.

## After the run

11. Both: `/reload`. That writes the probe's log to the saved variables.
12. Tell me what you saw and heard (panel, dings, chat lines). I read your
    log directly from your
    `_forever_\WTF\Account\<account>\SavedVariables\SakaMindProbe.lua`.
    It holds the paladin's results too, so their file is needed only if I
    ask for it: the same file in their own account folder.

## Follow-up tests (2026-11-11)

Both run on your client only. The paladin needs no update: his probe can
stay on or be turned off.

1. Solo, in town: type `/smp flags` and wait a few seconds for "flag check
   done". The probe checks Blizzard's yes/no flags of every spell and tells
   you how many other spells answer like Lay on Hands. Then `/reload` and
   tell me. Not run: the project was dropped on 2026-11-11 first.
2. Any dungeon, strangers too: nothing to do. After each boss the probe
   prints "party casts during the boss: …". It says whether party members'
   casts reached the probe mid-fight with a hidden spell ID, and how many
   of its test calls accepted that hidden ID. Done 2026-11-11 on trash:
   party casts barely arrive during your combat, and the calls accept
   hidden IDs (RESEARCH.md, party-cast test).

## What each result decides

| Result | What it means for SakaMind |
|---|---|
| Battle.net messages sent and received during the boss | Live updates in boss fights, Lay on Hands included, between Battle.net friends. Party messages stay the main route outside boss fights. |
| Battle.net sends return `AddOnMessageLockdown` | No live messages during boss fights. SakaMind syncs at the pull and after the kill. |
| A send at "lock starting" succeeds | SakaMind sends its last snapshot at the pull. |
| The paladin's Lay on Hands cast was readable in combat | The paladin's client knows about it at once (and can send it if Battle.net works). |
| Lay on Hands icon shown during the fight | SakaMind can show "Lay on Hands used" live without any message. |
| Damage meter readable only after the fight | SakaMind shows that Lay on Hands was used in the last fight, after it. |
| Defensive buffs shown on the panel | The live display works as planned. |
| Dings play | SakaMind can add a sound per defensive. |
| Some spell or Forbearance "never hidden" | SakaMind can time those uses live during the fight. |
| Lay on Hands answers Blizzard's flags unlike the paladin's other heals | The damage meter's hidden healing list can drive a light that shows only for Lay on Hands. |
