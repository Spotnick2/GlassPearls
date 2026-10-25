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
| #4 | Settings follow you across your accounts (automatic, per-key last-writer-wins) | done |
| #5 | PearlsProbe: what the client must confirm on day one | next (built after #6, owner 2026-10-25) |
| #6 | Bags full helper (pearl `bagsfull`) | built; its action waits for the probe |
| #10 | Map landmarks (pearl `landmarks`): entrances, boats, zeppelins, the tram, flight points, zone levels | built; its positions and icons wait for day one |
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

**Settings sync (#4)** (needs two of your accounts online on the same Battle.net account)
- [ ] `/gpearls sync` on both: the link sees the other account ("Battle.net: usable", a trusted peer).
- [ ] Switch a pearl or change a setting on one: it changes on the other within a few seconds,
      and `/gpearls sync` there says "last received … from <name>, 1 applied".
- [ ] Log the second account in after a change made while it was away: it catches up at login.
- [ ] Change different settings on both while one is offline, bring it back: both keep both changes.
- [ ] Sharing off on one (Settings): nothing is sent or applied either way.
- [ ] A near-full snapshot (a long keep list, #6) sends without a hitch (hashing ~130 ms, LibAccountSync README).

**The bags-full helper (#6)** (fill your bags with a few grey and white items first)
- [ ] **`DeleteCursorItem` from the window's button deletes the grey item** (one click), or
      `ADDON_ACTION_FORBIDDEN` names it: then "by hand" mode must show and the item stay in the bag.
      The reference addons call it from their own clicks; probe step 1 measures it first.
- [ ] **The loot follows** (`LootSlot` after `BAG_UPDATE_DELAYED`): the ring lands in the freed slot.
      If refused, the loot window stays and the player clicks the row (change it to "highlight the row").
- [ ] The full-bags error names (`GetGameMessageInfo`) for a corpse, a herb or ore node, a quest
      object and a quest reward; add them to `BF.FULL_ERRORS` (only `ERR_INV_FULL` is in so far).
- [ ] Loot that fits on a partial stack or in a herb / mining bag: no prompt.
- [ ] A white item: the first click says "Click again to destroy", the second destroys.
- [ ] The window sits right of the loot window; dragged, it stays where it was put after a /reload.
- [ ] Tooltips on both cards (Blizzard's bag and loot tooltips).
- [ ] The X: the item isn't offered again, on another character, and after a sync on another account.
- [ ] Auto-loot on: the helper still shows for the rows that didn't fit.
- [ ] Combat: it hides and comes back after.

**Map landmarks (#10)** (`Tools\landmarks\report.txt` lists each position's source and confidence)
- [ ] HereBeDragons-Pins loads from our copy (no Lua error; `/gpearls failures` names no `pearl landmarks`).
- [ ] **The icons sit where they belong** on the zone and the continent maps, and the minimap: walk
      or fly past a few "hand" entrances first (Blackrock Mountain, Dire Maul, Zul'Gurub, Onyxia's
      Lair, the four new Forever dungeons) and a few "client" ones; correct `entrances.csv` and
      regenerate. A swapped axis would put everything mirrored across the zone: check one first.
- [ ] Docks: Menethil, Auberdine's three piers, Ratchet, Booty Bay, the zeppelin towers, the
      Deeprun Tram ends, Stormwind Harbor, Tanaris and the Riverglades.
- [ ] The icons: which of the atlases (`Dungeon`, `Raid`, `TransportShip`, `TransportZeppelin`,
      `TransportTram`, `TaxiNode_Neutral`) the client has, and how the file fallback looks (screenshot).
- [ ] Tooltips: names (localized from `GetLFGDungeonInfo` when it gives them), level colours like
      Blizzard's zone label, "(Horde only)" on the other faction's zeppelins, the destinations.
- [ ] Clicks pass through to the map (zoom out with a right-click on an icon still works);
      NodeRadar's waypoints untouched.
- [ ] **Flight points away from a flight master:** does `C_TaxiMap.GetTaxiNodesForMap` answer
      in the open world? Where `ShouldMapShowTaxiNodes` is true, Blizzard's own pins must show and
      ours not (no doubles). Undiscovered ones greyed; `TAXI_NODE_STATUS_CHANGED` after learning one.
- [ ] **The zone level line:** hover a zone on the Kalimdor and Eastern Kingdoms maps: its range
      just under Blizzard's name (or its description line), only when Blizzard shows none
      (`C_Map.GetMapLevels`). Check where the
      area label provider's `Label` really is (`WorldMapFrame.dataProviders`).
- [ ] Switching it off in the window removes every pin at once; on again brings them back.

**The probe (#5):** its steps are added here by its PR.

## Candidate pearls after M1

Owner to fill in. For each: what it does, the client API it relies on (in the newest dump, and
measured with a ForeverProbe module where the dump can't say), its default, and whether it can
switch off live or needs a `/reload`.
