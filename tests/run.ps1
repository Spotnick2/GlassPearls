<#
    run.ps1 - Syntax-check the addon and run every tests\test_*.lua under Lua 5.1,
    through WowTestKit at the commit tests\kit.pin names (its scripts\run.ps1).

    Usage:
        pwsh tests/run.ps1
        pwsh tests/run.ps1 -Lua "C:\path\to\lua5.1.exe"
        pwsh tests/run.ps1 -KitDev      # the ..\WowTestKit working copy, not the pin
#>

param(
    [string]$Lua = "C:\Program Files (x86)\Lua\5.1\lua.exe",
    [switch]$KitDev
)

$ErrorActionPreference = "Stop"
$RepoRoot = Split-Path -Parent $PSScriptRoot

# The tests load the library checkouts as they are; CI loads the .pkgmeta pins.
. (Join-Path $RepoRoot "Tools\LibGlassPin.ps1")
$libGlass = if ($env:LIBGLASS) { $env:LIBGLASS } else { Join-Path (Split-Path -Parent $RepoRoot) "LibGlass" }
if (Test-Path -LiteralPath $libGlass) { Write-LibGlassPinStatus $RepoRoot $libGlass "CI tests the pin" }
$libSync = if ($env:LIBACCOUNTSYNC) { $env:LIBACCOUNTSYNC } else { Join-Path (Split-Path -Parent $RepoRoot) "LibAccountSync" }
if (Test-Path -LiteralPath $libSync) { Write-LibGlassPinStatus $RepoRoot $libSync "CI tests the pin" "Libs/LibAccountSync-1.0" }

. (Join-Path $PSScriptRoot "kit.ps1")
$kit = Get-WowTestKit -RepoRoot $RepoRoot -KitDev:$KitDev
& (Join-Path $kit "scripts\run.ps1") -RepoRoot $RepoRoot -Toc "GlassPearls.toc" -Lua $Lua
exit $LASTEXITCODE
