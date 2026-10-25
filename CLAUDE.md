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
independent feature the player switches on or off on its own. It wears WoW Forever's own look by
default and Glass UI's glass when Glass UI is installed (owner). The milestones, the plan and the
day-one checklist are [docs/PLAN.md](docs/PLAN.md).

**Status: M1 in progress** (docs/PLAN.md): the options window and the look (#3) are done; settings
sync (#4), the day-one probe (#5) and the first pearl, the bags-full helper (#6), follow. Nothing
has been measured in game for this addon: the client is unavailable until 2026-11-04, so every
client claim is on the day-one checklist in docs/PLAN.md.

## Layout

TOC load order: `Libs\LibGlass-1.0\LibGlass-1.0.xml` → `Libs\LibAccountSync-1.0\LibAccountSync-1.0.xml`
→ `Compat.lua` → `Theme.lua` → `UI.lua` → `AccountSync.lua` → `Pearls.lua` → *(pearl files,
`Pearls\<Name>.lua`)* → `Options.lua` → `GlassPearls.lua`. Pearls load after everything they may
use and before the options window and bootstrap.

- **`Compat.lua`**: `GlassPearls.API`, the only route to client APIs that moved or may be absent:
  `IsSecret`, `RegisterEvents` (reports failures), `NoteCombat` / `InCombat`, `Fail(key, err)` (the
  **one** failure recorder, read by `/gpearls failures`), `AddOnVersion`, `ClientBuild`,
  `SafeFrame` (a template and whether it applied, read raw); `MEASURED_ON_BUILD`. A subset of
  GlassMail's; lift more from there when a pearl needs it.
- **`Theme.lua`**: the look, fixed once at `ADDON_LOADED`. **WoW Forever by default**
  (`DialogBorderDarkTemplate`, Blizzard's fonts and widgets); **glass only from Glass UI**: with
  `## OptionalDeps: GlassUI`, when its suite speaks API 1 and "Use Glass UI appearance" is on, it
  builds the answered preset and the suite's body and accent, and reports (`live = false`,
  `declined` when turned off, `reason` on a failed build). The model is `..\Stakeout\Theme.lua`;
  the contract is `..\GlassUI\docs\SUITE.md`. No glass of our own choosing (owner). Helpers:
  `Window`, `Reading`, `Control`, `Accent`, `NewGlass`; `Active`, `Following`, `Glass`.
- **`UI.lua`**: the shared widgets (`Label`, `Header`, `Tooltip`, `Button`, `Check`, `Gear`,
  `Radios`, `Search`), Blizzard templates in both looks; a value control returns a `refresh`.
- **`Pearls.lua`**: the registry. `Pearls.Register{ key, name, desc, default, category, section,
  Enable, Disable, defaults, configure, help, onReset }`; `IsOn`, `IsLive`, `NeedsReload`,
  `PendingReload`, `Set`, `List`, `Categories` (in `CATEGORIES` order), `InCategory`, `Search`,
  `Setting` / `SetSetting` / `ResetSettings` (a pearl's own settings in
  `GlassPearlsDB.settings[key]`), `StartAll` (at login). Only what differs from a default is saved.
  `Enable` / `Disable` / `configure` / `onReset` run under `pcall`: a pearl that throws is recorded
  and the others keep running.
- **`AccountSync.lua`**: `GlassPearls.AccountSync`, one LibAccountSync-1.0 snapshot instance on
  the wire tag `"GlassPearls"` (**permanent: never change it**). `AS.On(kind, fn)`,
  `AS.Send(kind, body)`, `IsEnabled` / `SetEnabled`, `Lines()` for `/gpearls sync`. Payloads are
  `"<kind>\n<body>"`; handlers validate the body and never run it. The store is
  `GlassPearlsSyncDB`, its own SavedVariable, because it holds the household key: never fold it
  into `GlassPearlsDB` or anything exported. Its purpose here is keeping settings in sync across
  the owner's accounts (#4).
- **`Options.lua`**: **our own options window**, on Leatrix Plus's layout (the owner's choice;
  `References\Addons\Miscellaneous\LeatrixPlus`, All Rights Reserved: the layout is the model,
  nothing is copied). Left: the name, the version, Home, each category that has pearls, Settings.
  Right: two columns of sections, a checkbox per pearl, a gear opening its Configuration Panel in
  the same window (Reset, Help, Back to Main Menu), `*` after a pearl without `Disable`, Reload
  while a change waits, a search box. Built on first open, re-read on every show; Esc through
  `table.insert(UISpecialFrames, ...)` (never reassign it). Reload calls `ReloadUI()` from its own
  click (unmeasured: if `ADDON_ACTION_FORBIDDEN` names it, "Type /reload" replaces the button).
  Plus a small Esc > Options > AddOns page with an "Open Glass Pearls" button.
- **`GlassPearls.lua`**: bootstrap (saved settings, the look at `ADDON_LOADED`, login build
  warning), `GP.Settings`, and `/gpearls` (`/glasspearls`): no argument toggles the window. Loads last.

### Adding a pearl

1. `Pearls\<Name>.lua`, starting `GlassPearls = GlassPearls or {}`, calling
   `GlassPearls.Pearls.Register{...}` at file scope and doing **nothing else until `Enable`**
   (no frames registered for events, no hooks). The key is the saved key: lower-case letters or
   digits, permanent. Give it a `category` from `Pearls.CATEGORIES` and a `section`.
2. List it in the TOC after `Pearls.lua` (test_toc checks the order); the deploy script follows
   the TOC.
3. Give it a `Disable` that undoes `Enable` where the client allows it. Where it can't (a
   `hooksecurefunc` can't be removed), omit `Disable` or make the hook check `Pearls.IsOn`; the
   window then shows `*` and Reload.
4. Options: `defaults` for its settings, read with `Pearls.Setting`, written with
   `Pearls.SetSetting`; `configure(panel, refreshers)` builds its panel from `GP.UI` widgets and
   adds each control's `refresh`; `help` for the Help button.
5. A test file `tests\test_<name>.lua`, and a line in `CHANGELOG.md` under the next version.

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
and ChatThrottleLib for LibAccountSync, `WoW.installGlassUI` for a scriptable Glass UI suite,
`WoW.missingTemplates` for a template the client lacks, `WoW.reloadForbidden` for a refused
`ReloadUI`), `tests\harness.lua` (`check`, `eq`, `loadAddon` with an `opts.before` hook for
registering test pearls, `newChat`, `chatHas`). A stub is added only for something in the 70532
dump (documented functions or the `_G` walk) or Blizzard's source, and its comment says which.

**The unit tests are the main proof until 2026-11-04** (owner): one test file per concern, every
new assertion mutation-tested (break the behaviour, confirm it goes red; list them in the PR).
Offline tests can't cover taint, real secrets or rendering; that's PearlsProbe (#5) and the
day-one checklist.

## Workflow and releasing

- Every change goes through a GitHub issue → branch off `main` → PR with `Closes #N`. Never
  commit to `main`. `luac -p` clean and tests green before committing; check the PR's
  `package-check` run after pushing.
- **Never merge a PR without the owner's approval** (owner, 2026-10-25). The one exception: a
  documentation-only PR where a review would add nothing, which may be merged and reported. A PR
  touching `.github/workflows/`, the TOC or any Lua is never that.
- **Plans** get an adversarial review before coding (the `codex-consult` skill). Verify its
  claims; push back on complexity.
- **Releasing** follows `C:\Projects\WoW\References\Docs\RELEASING.md`; `package-check.yml` and
  `tests/release_files.sh` are its templates (only the `REPO-SPECIFIC` steps are this repo's).
  - CurseForge project **1764704** builds a release from every tag through its webhook and
    `.pkgmeta`. No CurseForge key lives in the repo, and the packager never uploads from CI.
  - The tag's run publishes CI's own checked zip as a GitHub Release (with `release.json`) and
    uploads it to Wago Addons, project **`kGr9LxKy`** (https://addons.wago.io/addons/kGr9LxKy),
    with the `WAGO_API_TOKEN` repo secret (set 2026-10-25).
  - The TOC carries both IDs (`X-Curse-Project-ID`, `X-Wago-ID`); test_toc checks them.
  - The notes are the tag's `## vX.Y.Z` section of `CHANGELOG.md`, which always has one: the
    release-files step reads the newest heading on every run and fails without one.
  - `README.curseforge.md` (gitignored) is the CurseForge and Wago description, pasted by hand.

## Conventions

- **Right-size for a single maintainer.** Each pearl stays small; the simplest thing that works,
  no speculative abstraction. A pearl that outgrows this addon becomes its own.
- **Measured beats reasoned.** If a claim about the client can be checked in game, check it.
- Match the surrounding code's idiom. Keep pure refactors in their own commit.
