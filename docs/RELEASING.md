# Releasing

Decided on 2026-11-10: SakaMind is published on CurseForge from the
player's own account, under the MIT license ([LICENSE](../LICENSE)), and
built from this public GitHub repository,
<https://github.com/CynGames/SakaMind>. The test add-on, SakaMind Probe,
goes out the same way first, as files of the SakaMind project. The paladin
installs it with the CurseForge app and gets each new version as an update,
instead of copying zips.

## How a release is built

Pushing a tag that starts with `v` starts
[.github/workflows/release.yml](../.github/workflows/release.yml), which
runs the BigWigs packager (`BigWigsMods/packager@v2`, the tool most WoW
add-ons use). The packager:

- copies the add-on folder named in [.pkgmeta](../.pkgmeta)
  (`SakaMindProbe` for now), adds `LICENSE` and a changelog made from the
  commit messages, and leaves out `docs/`, `README.md` and `AGENTS.md`;
- writes the tag into the TOC's `## Version: @project-version@`;
- reads `## Interface: 16001` and marks the file for WoW Forever, game
  version 1.60.1;
- uploads the zip to CurseForge (the project comes from the TOC's
  `## X-Curse-Project-ID`, the token from the `CF_API_TOKEN` secret) and to
  a GitHub release for the tag. Without the project ID or the token it
  skips CurseForge and only makes the GitHub release.

The tag decides the file type: a tag with "alpha" or "beta" in it makes an
alpha or beta file, and any other tag a release file. Probe builds are
release files (`v0.1.0`, `v0.1.1`, ...), because CurseForge's app lists a
project only once it has at least one release file ([CurseForge known
issues](https://support.curseforge.com/support/solutions/articles/9000196615-known-issues)).

A dry run on 2026-11-10 (the packager on a copy, without upload or zip)
gave the expected package: one `SakaMindProbe` folder holding the TOC,
`Probe.lua`, `LICENSE` and `CHANGELOG.md`, version `v0.1.0`, game version
1.60.1.

## One-time setup

1. CurseForge, on the player's account: create the project "SakaMind" for
   World of Warcraft, license MIT, not marked Experimental. The project ID
   is in its "About Project" box. CurseForge reviews new projects before
   they go public.
2. CurseForge: create an API token at
   <https://authors.curseforge.com/#/settings/api-tokens>.
3. GitHub, in the repository's Settings > Secrets and variables > Actions:
   add that token as the secret `CF_API_TOKEN`.
4. Here: add `## X-Curse-Project-ID: <ID>` to the TOC.

Status, 2026-11-10: the GitHub repository and its `CF_API_TOKEN` secret are
set up. The CurseForge project and its ID in the TOC are still to come.

## Making a release

Only when the player asks:

1. Run luacheck, commit and push `master`. The commit messages since the
   last tag become the changelog on CurseForge, so write them for players.
2. Make an annotated tag (the packager needs annotated tags) and push it:
   `git tag -a v0.1.0 -m "SakaMind Probe 0.1.0"`, then
   `git push origin v0.1.0`.
3. Check the run in the repository's Actions tab, then the file on
   CurseForge, which shows once CurseForge has processed it.

## When SakaMind itself is ready

Point `.pkgmeta` at the new folder (`package-as: SakaMind` and a
`SakaMind/SakaMind: SakaMind` move), give its TOC the same project ID, and
keep counting versions up from the probe's. Check that the CurseForge app's
update removes the `SakaMindProbe` folder; if it doesn't, players have to
delete the probe by hand.
