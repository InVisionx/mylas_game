# Publish the APK as a GitHub Release asset (gives you a short, permanent URL).
#
#   $env:GITHUB_TOKEN = "ghp_your_token_with_repo_scope"
#   powershell -ExecutionPolicy Bypass -File tools\publish_release.ps1 -Version 0.1.0
#
# Resulting URL (works in the G Cloud browser):
#   https://github.com/InVisionx/mylas_game/releases/latest/download/NightShift-NotHuman.apk
#
# The plain repo link works without any of this:
#   https://github.com/InVisionx/mylas_game/raw/main/dist/NightShift-NotHuman.apk

param(
    [string]$Version = "0.1.0",
    [string]$Owner = "InVisionx",
    [string]$Repo = "mylas_game"
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$apk = Join-Path $root 'dist\NightShift-NotHuman.apk'

if (-not $env:GITHUB_TOKEN) { throw "Set GITHUB_TOKEN to a personal access token with 'repo' scope." }
if (-not (Test-Path $apk)) { throw "APK not found at $apk" }

$headers = @{
    Authorization          = "Bearer $($env:GITHUB_TOKEN)"
    Accept                 = 'application/vnd.github+json'
    'X-GitHub-Api-Version' = '2022-11-28'
    'User-Agent'           = 'NightShift-Release'
}

$tag = "v$Version"
$notes = @"
Night Shift: Not Human $Version

Android release build for the Logitech G Cloud.

Install: download the APK, open it from Files -> Downloads, allow install from unknown apps.
"@

$body = @{ tag_name = $tag; name = "Night Shift: Not Human $Version"; body = $notes; draft = $false; prerelease = $false } | ConvertTo-Json
Write-Output "Creating release $tag..."
$release = Invoke-RestMethod -Uri "https://api.github.com/repos/$Owner/$Repo/releases" -Method Post -Headers $headers -Body $body -ContentType 'application/json'

$uploadUrl = ($release.upload_url -replace '\{.*\}', '') + "?name=NightShift-NotHuman.apk"
Write-Output "Uploading APK ($([math]::Round((Get-Item $apk).Length / 1MB, 1)) MB)..."
$uploadHeaders = $headers.Clone()
$uploadHeaders['Content-Type'] = 'application/vnd.android.package-archive'
Invoke-RestMethod -Uri $uploadUrl -Method Post -Headers $uploadHeaders -InFile $apk -TimeoutSec 600 | Out-Null

Write-Output "Done: https://github.com/$Owner/$Repo/releases/latest/download/NightShift-NotHuman.apk"
