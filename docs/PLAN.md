# Glass Pearls: plan

## M0: scaffold (done, 2026-10-25)

Repo, TOC, `.pkgmeta` with LibGlass r11 and LibAccountSync r5 pinned, CI (tests at the pins,
packager dry run, exact zip contents, GitHub Release and Wago upload on a tag), deploy script, the
pearl registry, `/gpearls`, the own-account link. Release setup in #1/#2 (CurseForge 1764704,
Wago `kGr9LxKy`).

## M1: the bags-full helper and the foundations it needs (v0.1.0)

Reviewed adversarially with Codex before coding (7 rounds, consensus on 2026-10-25). Built blind:
the client is unavailable until 2026-11-04, so every client claim is checked against the 70532 API
dump and `wow-ui-source`, covered by unit tests, and listed below for day one. **No v0.1.0 tag
until PearlsProbe's steps 1-3 pass** and the code is adjusted to what they show.

| Issue | What | State |
|---|---|---|
| #3 | The options window (Leatrix Plus's layout) and the look: WoW Forever by default, Glass UI's when present | done |
| #4 | Settings follow you across your accounts (automatic, per-key last-writer-wins) | next |
| #5 | PearlsProbe: what the client must confirm on day one | before #6's action |
| #6 | Bags full helper (pearl `bagsfull`) | after #5 |
| GlassUI#163 | Glass UI lists Glass Pearls as a dynamic member | Glass UI's session |

## Waiting for the client (day one: 2026-11-04)

Each line is a claim the code relies on that only the live client can settle.

**The scaffold and the window (#3)**
- [ ] Loads clean (`/console scriptErrors 1`, `/reload`, `/gpearls failures` says none).
- [ ] `/gpearls` opens the window; Esc closes it; it drags; it opens in combat.
- [ ] The Forever look: `DialogBorderDarkTemplate` renders as Blizzard's dark dialog (screenshot).
- [ ] The search box (`SearchBoxTemplate`) shows "Search options" and its clear button.
- [ ] The gear texture (`Interface\WorldMap\GEAR_64GREY`) shows beside a pearl with options.
- [ ] **Reload: `ReloadUI()` from the button's own click reloads, or raises
      `ADDON_ACTION_FORBIDDEN`** (the porting guide calls it protected; Leatrix Plus's Forever build
      calls it from a click). If refused, the button gives way to "Type /reload" (built, tested).
- [ ] With Glass UI (after GlassUI#163): glass windows, `/glassui suite` lists Glass Pearls as
      following; unticking "Use Glass UI appearance" + reload gives the Forever look, listed as declined.
- [ ] The Esc > Options > AddOns page shows on its first visit and its button opens the window.
- [ ] `GlassPearlsDB`, `GlassPearlsCharDB`, `GlassPearlsSyncDB` are written after a full client exit.
- [ ] The client build is still 1.60.1.70532; if not, a new dump (`forever-api-dump` skill).

**Settings sync (#4), the probe (#5), the bags-full helper (#6):** their checks are added here by
their PRs.

## Candidate pearls after M1

Owner to fill in. For each: what it does, the client API it relies on (in the newest dump, and
measured with a ForeverProbe module where the dump can't say), its default, and whether it can
switch off live or needs a `/reload`.
