# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

GlassPearls is a **quality-of-life addon for World of Warcraft: Forever 1.60.1** (Interface
`16001`), written in **Lua 5.1**. It has a single owner (Spotnick) and uses the same stack and
conventions as the sibling Forever addons: `..\GlassChat` (the template for this repo's tooling,
tests and CI, and the pilot consumer of LibAccountSync) and `..\GlassMail` (the closest in size and
shape). When this file doesn't cover something, check how those handle it before you invent a new
idiom.

**Goal:** many small quality-of-life touches in one addon, each one a **pearl**: a small,
independent feature the player switches on or off on its own, in the Glass look where it draws
anything. The candidate list and the milestones are [docs/PLAN.md](docs/PLAN.md).

**Status: scaffold.** The registry, the options page, the own-account link and the tooling are in
place; there are no pearls yet. Nothing has been measured in game for this addon.

## Layout

TOC load order: `Libs\LibGlass-1.0\LibGlass-1.0.xml` → `Libs\LibAccountSync-1.0\LibAccountSync-1.0.xml`
→ `Compat.lua` → `Glass.lua` → `AccountSync.lua` → `Pearls.lua` → *(pearl files,
`Pearls\<Name>.lua`)* → `Options.lua` → `GlassPearls.lua`. Pearls load after everything they may
use and before the options page and bootstrap.

- **`Compat.lua`**: `GlassPearls.API`, the only route to client APIs that moved or may be absent:
  `IsSecret`, `RegisterEvents` (reports failures), `NoteCombat` / `InCombat`, `Fail(key, err)` (the
  **one** failure recorder, read by `/gpearls failures`), `AddOnVersion`, `ClientBuild`;
  `MEASURED_ON_BUILD`. A subset of GlassMail's; lift more from there when a pearl needs it.
- **`Glass.lua`**: `GlassPearls.Glass`, this addon's instance of LibGlass-1.0 with the suite's
  `"pearl"` preset (r11; an older dev copy falls back to its default material).
- **`Pearls.lua`**: the registry. `Pearls.Register{ key, name, desc, default, Enable, Disable }`,
  `IsOn`, `IsLive`, `Set`, `List`, `StartAll` (at login). Choices are saved in
  `GlassPearlsDB.pearls[key]`, only when they differ from the pearl's default. `Enable` / `Disable`
  run under `pcall`: a pearl that throws is recorded and the others keep running.
- **`AccountSync.lua`**: `GlassPearls.AccountSync`, one LibAccountSync-1.0 snapshot instance on
  the wire tag `"GlassPearls"` (**permanent: never change it**). `AS.On(kind, fn)`,
  `AS.Send(kind, body)`, `IsEnabled` / `SetEnabled`, `Lines()` for `/gpearls sync`. Payloads are
  `"<kind>\n<body>"`; handlers validate the body and never run it. The store is
  `GlassPearlsSyncDB`, its own SavedVariable, because it holds the household key: never fold it
  into `GlassPearlsDB` or anything exported. A pearl needing a second snapshot kind or the
  messages mode gets its own instance on its own tag over the same store (GlassChat's
  `GlassChatST`, LibAccountSync#17).
- **`Options.lua`**: Esc > Options > AddOns > Glass Pearls, the porting guide's measured recipe
  (hidden at creation, built on the first `OnShow`, re-read on every show, registered once at
  `PLAYER_LOGIN`). One checkbox per pearl, then the own-account switch.
- **`GlassPearls.lua`**: bootstrap (saved settings, login build warning) and `/gpearls`
  (`/glasspearls`). Loads last.

### Adding a pearl

1. `Pearls\<Name>.lua`, starting `GlassPearls = GlassPearls or {}`, calling
   `GlassPearls.Pearls.Register{...}` at file scope and doing **nothing else until `Enable`**
   (no frames registered for events, no hooks). The key is the saved key: lower-case letters or
   digits, permanent.
2. List it in the TOC after `Pearls.lua` (test_toc checks the order); the deploy script follows
   the TOC.
3. Give it a `Disable` that undoes `Enable` where the client allows it. Where it can't (a
   `hooksecurefunc` can't be removed), omit `Disable` or make the hook check `Pearls.IsOn`; the
   registry then reports "after /reload".
4. A test file `tests\test_<name>.lua`, and a line in `CHANGELOG.md` under Unreleased.

## Forever basics (shared with the siblings)

- One plain `GlassPearls.toc`, `## Interface: 16001` (**`11601` is a transposed-digit bug**).
  Never commit a literal version over `@project-version@`; the deploy script writes `dev` into its
  copy.
- One global namespace, `GlassPearls`; files start `GlassPearls = GlassPearls or {}` and alias it
  `local GP = GlassPearls`. A `_test` seam table exposes file-local internals to tests.
- **Extend Blizzard's UI; never replace it.** Only `hooksecurefunc`, `HookScript` and addon-owned
  frames. Never reassign a Blizzard global or method, never write a field onto a Blizzard frame.
- **Secret values:** test with `issecretvalue(v)` **before** any other use; never save one.
- **`RegisterEvent` throws on unknown names and returns `false` for refusals**: always
  `API.RegisterEvents`.
- `ReloadUI()` is protected. Options use `Settings.RegisterCanvasLayoutCategory`.
- SavedVariables persist as of 70009; read them at `ADDON_LOADED` / `PLAYER_LOGIN`, cope when
  they're absent, and **verify persistence only with a full client exit**.
- **IDs, never names**: never compare against or save an English display string (localized
  clients).

## References: read these before touching an unfamiliar API

- `C:\Projects\WoW\References\Docs\PORTING-TBC-TO-FOREVER.md`: measured, addon-agnostic field
  notes. Treat them as fact. New addon-agnostic findings go there, not into a copy here.
- `C:\Projects\WoW\References\Forever\api\`: the API dumps; use the highest build (the root
  CLAUDE.md's rule). This repo was made against 1.60.1.70532. **Presence is not a contract.**
- `C:\Projects\WoW\References\Docs\EMBEDDED-LIBRARIES.md`, `LIBGLASS-MIGRATION.md`: library rules.
  `..\LibGlass\README.md` and `..\LibAccountSync\README.md`: the two libraries' contracts.
- `C:\Projects\WoW\wow-ui-source` (branch `forever`): the client's own FrameXML; line numbers match
  in-game error traces.
- `C:\Projects\WoW\References\Addons\`: third-party addons as **behaviour references only**. Check
  each one's licence before reading closely, and never copy code from one that isn't permissive.
  This repo is MIT.

## Toolchain and commands

Lua 5.1 at `C:\Program Files (x86)\Lua\5.1\` (`lua.exe`, `luac.exe`). No build step.

```powershell
pwsh tests\run.ps1                                                   # luac -p on the TOC files, then every tests\test_*.lua (needs ..\LibGlass and ..\LibAccountSync, or $env:LIBGLASS / $env:LIBACCOUNTSYNC)
& 'C:\Program Files (x86)\Lua\5.1\lua.exe' tests\test_boot.lua      # one test, from the repo root
pwsh Tools\deploy.ps1                                                # copy the addon and both libraries into AddOns
```

- Default AddOns path: `C:\Program Files (x86)\World of Warcraft\_forever_\Interface\AddOns`
  (`-AddOnsPath` to change).
- In game: `/console scriptErrors 1` first, then `/reload`. A brand-new addon folder no longer
  needs a client restart, unless it brings new textures (owner, 2026-10-09; see the porting guide).
- The tests load the sibling library checkouts as they are and warn when one is off its `.pkgmeta`
  pin; CI fetches the pins (`tests\fetch_external.sh`) and also checks the packaged zip's exact
  contents.
- Shell heredocs in this environment can collapse `\\` to `\`: write files that contain Lua
  backslash escapes or Windows paths with the Write/Edit tools.

## Testing

GlassMail's harness, plus GlassChat's Battle.net stubs: `tests\wow_stubs.lua` (strict globals as
an allowlist of APIs verified in the dump, secrets as throwing `newproxy` values, event names
validated against the dump or `tests\events-70532.txt`, every widget method recorded, Battle.net
and ChatThrottleLib for LibAccountSync), `tests\harness.lua` (`check`, `eq`, `loadAddon` with an
`opts.before` hook for registering test pearls, `newChat`, `chatHas`). **Mutation-test every new
test**: break the behaviour, confirm it goes red. Offline tests can't cover taint, real secrets or
rendering; that's a ForeverProbe module (`References\Docs\PROBES.md`) and an in-game check.

## Workflow and releasing

Same as GlassChat's CLAUDE.md, "Workflow and releasing":
- Issue → branch off `main` → PR with `Closes #N`. Never commit to `main`; commit or push only
  when asked. `luac -p` clean and tests green before committing; check the PR's `package-check`
  run after pushing.
- **The owner merges and closes PRs and launches reviews.**
- **Plans** get an adversarial review before coding (the `codex-consult` skill). Verify its
  claims; push back on complexity.
- CurseForge builds releases from the tag webhook through `.pkgmeta` (`References\Docs\RELEASING.md`);
  the `release` job publishes a GitHub Release from the tag's `## vX.Y.Z` section of
  `CHANGELOG.md`. The CurseForge project doesn't exist yet: add `## X-Curse-Project-ID` to the TOC
  once it does.

## Conventions

- **Right-size for a single maintainer.** Each pearl stays small; the simplest thing that works,
  no speculative abstraction. A pearl that outgrows this addon becomes its own.
- **Measured beats reasoned.** If a claim about the client can be checked in game, check it.
- Match the surrounding code's idiom. Keep pure refactors in their own commit.
