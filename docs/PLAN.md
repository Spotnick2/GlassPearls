# Glass Pearls: plan

## M0: scaffold (done, 2026-10-25)

- Repo, TOC, `.pkgmeta` with LibGlass r11 and LibAccountSync r5 pinned, CI (tests at the pins,
  packager dry run, exact zip contents, GitHub Release on a tag), deploy script.
- The pearl registry (`Pearls.lua`), options page, `/gpearls`, the own-account link
  (`AccountSync.lua`, tag `GlassPearls`, store `GlassPearlsSyncDB`).
- Not done: a GitHub remote, a CurseForge project, an in-game check of the scaffold.

## Waiting for the client (game unavailable until 2026-11-04)

The beta closed on 2026-10-24, so everything until launch is built from the API dump,
wow-ui-source and the offline tests. Each claim that only the client can settle goes here and is
checked on the first day back.

- [ ] The scaffold loads clean (`/console scriptErrors 1`, `/reload`, `/gpearls failures` says none).
- [ ] The options page shows on its first visit (not blank), with "No pearls yet." and the sync box.
- [ ] `/gpearls sync` prints the LibAccountSync readout for the `GlassPearls` tag.
- [ ] `GlassPearlsDB`, `GlassPearlsCharDB` and `GlassPearlsSyncDB` are written after a full client exit.
- [ ] The client build is still 1.60.1.70532 at launch; if not, a new dump (`forever-api-dump` skill).

## Candidate pearls

Owner to fill in. For each: what it does, the client API it relies on (checked in the newest API
dump and, where the dump can't say, measured with a ForeverProbe module), its default, and whether
it can be switched off live or needs a `/reload`.

| Key | Pearl | Notes |
| --- | --- | --- |
| | | |

## Next

M1: the first handful of pearls, chosen by the owner, with a reviewed plan before coding.
