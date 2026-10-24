# Cuts a new build and publishes it so the handheld can auto-detect the update.
#
#   powershell -ExecutionPolicy Bypass -File tools\publish_update.ps1 -Version 0.2.0 -Notes "Fixed X"
#
# It: bumps the version in project.godot + export_presets.cfg, rebuilds the APK,
# writes dist/version.json (the manifest the game checks on launch), then commits
# and pushes. Use -NoPush to build locally only.

param(
    [Parameter(Mandatory = $true)][string]$Version,
    [int]$Code = 0,
    [string]$Notes = "",
    [switch]$NoPush
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
Set-Location $root

$godot = $env:GODOT
if (-not $godot) {
    $godot = 'C:\Users\mattm\Desktop\godot\Godot_v4.7.1-stable_win64.exe\Godot_v4.7.1-stable_win64_console.exe'
}
if (-not (Test-Path $godot)) { throw "Godot console executable not found. Set `$env:GODOT." }

function Read-Text([string]$path) { return [System.IO.File]::ReadAllText($path) }
function Write-Text([string]$path, [string]$text) {
    [System.IO.File]::WriteAllText($path, $text, (New-Object System.Text.UTF8Encoding($false)))
}

$projectPath = Join-Path $root 'project.godot'
$presetPath = Join-Path $root 'export_presets.cfg'
$project = Read-Text $projectPath

# --- Work out the new build number -----------------------------------------
$currentCode = 1
if ($project -match '(?m)^version_code=(\d+)') { $currentCode = [int]$Matches[1] }
if ($Code -le 0) { $Code = $currentCode + 1 }

# --- Update project.godot ---------------------------------------------------
if ($project -match 'config/version="[^"]*"') {
    $project = $project -replace 'config/version="[^"]*"', "config/version=`"$Version`""
} else {
    $project = $project -replace '(?m)^(config/name=.*)$', "`$1`nconfig/version=`"$Version`""
}
if ($project -match '(?m)^version_code=\d+') {
    $project = $project -replace '(?m)^version_code=\d+', "version_code=$Code"
} elseif ($project -match '(?m)^\[night_shift\]') {
    $project = $project -replace '(?m)^\[night_shift\]', "[night_shift]`nversion_code=$Code"
} else {
    $project = $project.TrimEnd() + "`n`n[night_shift]`n`nversion_code=$Code`n"
}
Write-Text $projectPath $project

# --- Update export preset ---------------------------------------------------
$preset = Read-Text $presetPath
$preset = $preset -replace '(?m)^version/code=\d+', "version/code=$Code"
$preset = $preset -replace '(?m)^version/name="[^"]*"', "version/name=`"$Version`""
Write-Text $presetPath $preset

# --- Build ------------------------------------------------------------------
New-Item -ItemType Directory -Force -Path (Join-Path $root 'dist') | Out-Null
$apk = Join-Path $root 'dist\NightShift-NotHuman.apk'
Write-Output "Building v$Version (code $Code)..."
& $godot --headless --path $root --export-release 'Android' $apk
if ($LASTEXITCODE -ne 0 -or -not (Test-Path $apk)) { throw 'Android export failed.' }

# --- Manifest ---------------------------------------------------------------
$hash = (Get-FileHash $apk -Algorithm SHA256).Hash
$sizeMb = [math]::Round((Get-Item $apk).Length / 1MB, 1)
$manifest = [ordered]@{
    code      = $Code
    name      = $Version
    apk_url   = 'https://github.com/InVisionx/mylas_game/raw/main/dist/NightShift-NotHuman.apk'
    notes     = $Notes
    sha256    = $hash
    size_mb   = $sizeMb
    released  = (Get-Date).ToString('yyyy-MM-dd')
}
$manifest | ConvertTo-Json | Set-Content -Path (Join-Path $root 'dist\version.json') -Encoding utf8
Write-Text (Join-Path $root 'dist\SHA256.txt') ("SHA256  $hash  NightShift-NotHuman.apk")

if (-not (Test-Path (Join-Path $root 'dist\version.json'))) { throw 'version.json was not written.' }
if ((Get-Item (Join-Path $root 'dist\version.json')).Length -lt 40) { throw 'version.json is empty.' }

Write-Output "APK: $apk ($sizeMb MB)"
Write-Output "version.json code=$Code name=$Version"

# --- Publish ----------------------------------------------------------------
if (-not $NoPush) {
    git add project.godot export_presets.cfg dist/NightShift-NotHuman.apk dist/version.json dist/SHA256.txt
    git commit -m "Release v$Version (build $Code)"
    git push origin main
    Write-Output "Pushed. Players will be offered the update on next launch."
}
