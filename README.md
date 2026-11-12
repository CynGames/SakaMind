# SakaMind

A WoW Forever add-on that was meant to share defensive cooldowns within a
core party. **Discontinued on 2026-11-11.** This repository is archived and
kept as a record.

Its tests showed that the game doesn't let add-ons share this during boss
fights, where it mattered most:

- Add-on messages are locked for the whole boss fight on every channel
  (party, whisper and Battle.net), even when sent from a key press.
- Party members' casts barely reach add-ons while you are in combat.
- Blizzard's damage meter shows a party member's Lay on Hands during the
  fight, but only as a hidden value: an add-on can display it, not read it,
  so it can't count down the cooldown.

The details are in [docs/RESEARCH.md](docs/RESEARCH.md) and
[docs/TEST-RUN.md](docs/TEST-RUN.md).

## The test add-on

SakaMind Probe, the test add-on, is no longer maintained. To remove it,
uninstall "SakaMind" in the CurseForge app, or delete the `SakaMindProbe`
folder from `World of Warcraft\_forever_\Interface\AddOns\`.

## License

MIT, see [LICENSE](LICENSE). Releases were built as described in
[docs/RELEASING.md](docs/RELEASING.md).
