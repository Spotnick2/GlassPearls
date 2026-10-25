<#
    deploy.ps1 - Copy GlassPearls into the Forever AddOns folder.

    The repo keeps "## Version: @project-version@" for the packager; the deployed
    copy gets "dev". The repo copy is never modified.

    The embedded libraries are LibGlass-1.0 and LibAccountSync-1.0. The packager
    fetches them into Libs\ (.pkgmeta externals); for a dev copy this script
    hands that job to each checkout's own deploy.ps1, which checks the checkout,
    copies only the shipped files and prints its commit. The checkouts are
    $env:LIBGLASS / $env:LIBACCOUNTSYNC, else ..\LibGlass / ..\LibAccountSync
    (GlassChat's pattern).

    The files copied are the TOC and every Lua file it lists (Pearls\ included),
    so a new pearl deploys once it is in the TOC.

    Usage:
        pwsh Tools/deploy.ps1
        pwsh Tools/deploy.ps1 -AddOnsPath "D:\...\_forever_\Interface\AddOns"
#>

param(
    [string]$AddOnsPath = "C:\Program Files (x86)\World of Warcraft\_forever_\Interface\AddOns"
)

$ErrorActionPreference = "Stop"
$RepoRoot = Split-Path -Parent $PSScriptRoot
if (-not (Test-Path $AddOnsPath)) { Write-Error "AddOns path not found: $AddOnsPath"; exit 1 }

. (Join-Path $PSScriptRoot "LibGlassPin.ps1")
$Parent = Split-Path -Parent $RepoRoot
$LibGlass = if ($env:LIBGLASS) { $env:LIBGLASS } else { Join-Path $Parent "LibGlass" }
$LibSync = if ($env:LIBACCOUNTSYNC) { $env:LIBACCOUNTSYNC } else { Join-Path $Parent "LibAccountSync" }

# The libraries first: their deploys check the checkout and may refuse, and a
# refusal must leave the deployed addon as it was (a new TOC naming a library
# that never arrived loads no frames at all).
foreach ($lib in @(
    @{ Name = "LibGlass"; Path = $LibGlass; Env = "LIBGLASS"; Pin = "Libs/LibGlass-1.0" },
    @{ Name = "LibAccountSync"; Path = $LibSync; Env = "LIBACCOUNTSYNC"; Pin = "Libs/LibAccountSync-1.0" }
)) {
    if (-not (Test-Path -LiteralPath (Join-Path $lib.Path "Tools\deploy.ps1"))) {
        Write-Error "$($lib.Name) checkout not found at $($lib.Path) (clone github.com/Spotnick2/$($lib.Name) there, or set `$env:$($lib.Env))"
        exit 1
    }
    Write-LibGlassPinStatus $RepoRoot $lib.Path "this deploy tests a library the release won't ship" $lib.Pin
    & pwsh -NoProfile -File (Join-Path $lib.Path "Tools\deploy.ps1") -Addon GlassPearls -AddOnsPath $AddOnsPath
    if ($LASTEXITCODE -ne 0) { Write-Error "$($lib.Name) deploy refused; GlassPearls was not touched"; exit 1 }
}

$dest = Join-Path $AddOnsPath "GlassPearls"
Write-Host "Deploying GlassPearls -> $dest" -ForegroundColor Cyan
New-Item -ItemType Directory -Force -Path $dest | Out-Null
$tocPath = Join-Path $RepoRoot "GlassPearls.toc"
$files = @("GlassPearls.toc") + @(Get-Content -LiteralPath $tocPath | ForEach-Object { $_.Trim() } |
    Where-Object { $_ -notmatch "^#" -and $_ -match "[.]lua$" })
foreach ($f in $files) {
    $src = Join-Path $RepoRoot $f
    $out = Join-Path $dest $f
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $out) | Out-Null
    if ($f -like "*.toc") {
        (Get-Content -LiteralPath $src -Raw) -replace '## Version: @project-version@', '## Version: dev' |
            Set-Content -LiteralPath $out -NoNewline
    } else {
        Copy-Item -LiteralPath $src -Destination $out -Force
    }
    Write-Host "  $f"
}
# A Lua file dropped from the TOC must not linger where the client finds it.
# Libs\ belongs to the libraries' own deploys.
$keep = $files | ForEach-Object { $_ -replace '/', '\' }
Get-ChildItem -LiteralPath $dest -File -Recurse | Where-Object {
    $rel = $_.FullName.Substring($dest.Length + 1)
    -not $rel.StartsWith("Libs\") -and $keep -notcontains $rel
} | ForEach-Object {
    Write-Host "  removing stale $($_.FullName.Substring($dest.Length + 1))" -ForegroundColor DarkYellow
    Remove-Item -LiteralPath $_.FullName -Force
}

Write-Host ""
Write-Host "Changed or new files, a brand-new addon folder included: /reload is enough (porting guide, 2026-10-09)." -ForegroundColor Yellow
Write-Host "In game:  /console scriptErrors 1   then   /gpearls (the options window)" -ForegroundColor Green
