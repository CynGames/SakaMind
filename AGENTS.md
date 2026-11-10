# Project instructions

SakaMind is a WoW Forever add-on for a core party (a paladin, a druid and
the player's priest) to share defensive cooldowns between their characters.
Read [docs/RESEARCH.md](docs/RESEARCH.md) first: it holds what the client
allows, above all during boss fights. The design isn't agreed yet. The test
add-on `SakaMindProbe` runs first ([docs/TEST-RUN.md](docs/TEST-RUN.md)).

The paladin wrote SakaBind (on CurseForge, MIT license); the SakaMind name
belongs to the same family and was agreed on 2026-11-10. SakaMind is
published on CurseForge from the player's account, MIT license, built from
this public GitHub repository; the probe goes out the same way first
([docs/RELEASING.md](docs/RELEASING.md)).

## Rules

- Target only WoW Forever: TOC `## Interface: 16001`, retail Midnight 12.1.5
  API with secret values. Don't use Classic-only APIs or the combat log.
- In combat, never compare or calculate with values that may be secret. Pass
  them to widgets, curves or duration objects instead, and guard with
  `issecretvalue` where a value may be secret.
- Make secure changes (bindings, attributes, showing or moving secure frames)
  only out of combat; queue them until combat ends when needed.
- Add-on messages are blocked during boss fights (the chat lock): queue them
  and send when the lock ends. Battle.net game data during boss fights is an
  experiment the player chose on 2026-11-10; keep it a separate route that
  SakaMind can do without if Blizzard blocks it.
- Every party member installs SakaMind: keep it small, quiet and usable by
  any class. No third-party libraries.
- Use the installed DBM code as reference for what works on this client
  (`C:\Program Files (x86)\World of Warcraft\_forever_\Interface\AddOns\`).
  Don't modify other add-ons or the game's WTF files.
- Published builds follow Blizzard's UI Add-On Development Policy: free,
  readable (not obfuscated) code, no ads or donation requests in game, and
  light message traffic (send on change, not on a timer). The probe's timed
  test messages go only to other probe users.
- The repository is public: no account names or numbers, saved-variable
  contents or other personal details in files or commit messages.
- Record design decisions in `docs/`.

## Checks and testing

- Static check, from the repo root:
  `& "$env:LOCALAPPDATA\Programs\luacheck\luacheck.exe" SakaMindProbe`
  (configuration in `.luacheckrc`).
- The game loads `SakaMindProbe/` through a junction at
  `C:\Program Files (x86)\World of Warcraft\_forever_\Interface\AddOns\SakaMindProbe`.
- A new add-on folder or a TOC change needs a full game restart; Lua changes
  need only `/reload`.
- Only the player can run the game, and some tests need the paladin running
  the same add-on. Hand over a short in-game checklist, then read
  `_forever_\Logs\FrameXML.log` (load errors) and the add-on's saved
  variables in the player's folder under `_forever_\WTF\Account\` (look it
  up locally; don't write it into the repository). The paladin sends their
  saved variables file.
- The paladin installs the probe from CurseForge, or from the zip on the
  GitHub release until the CurseForge project is live.

## Git

- Commit, push or tag only when the user asks. A pushed `v...` tag publishes
  a release ([docs/RELEASING.md](docs/RELEASING.md)).
- The repository is `CynGames/SakaMind` on GitHub. Commit as `CynGames`
  with its no-reply address `56620943+CynGames@users.noreply.github.com`,
  never with a personal email. A fresh clone needs this set in its local git
  config, together with `credential.https://github.com.username CynGames`
  so that pushes use the CynGames login.
- No AI attribution in commit messages or pull requests: no
  "Co-Authored-By" lines for AI tools and no "Generated with" lines.
