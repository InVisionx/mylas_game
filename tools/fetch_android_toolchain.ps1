# Fetch the Android export toolchain for Night Shift (background-friendly).
$ErrorActionPreference = 'Stop'
$dl = Join-Path $env:TEMP 'nightshift_dl'
New-Item -ItemType Directory -Force -Path $dl | Out-Null
Write-Output "Downloading into $dl"

$tpz = Join-Path $dl 'export_templates.tpz'
if (-not (Test-Path $tpz) -or (Get-Item $tpz).Length -lt 500MB) {
    Write-Output 'Fetching Godot export templates (1.2 GB)...'
    & curl.exe -L --retry 3 --fail -o $tpz 'https://github.com/godotengine/godot/releases/download/4.7.1-stable/Godot_v4.7.1-stable_export_templates.tpz'
    if ($LASTEXITCODE -ne 0) { throw "templates download failed ($LASTEXITCODE)" }
}

$cmdtools = Join-Path $dl 'commandlinetools-win.zip'
if (-not (Test-Path $cmdtools) -or (Get-Item $cmdtools).Length -lt 100MB) {
    Write-Output 'Fetching Android command-line tools (146 MB)...'
    & curl.exe -L --retry 3 --fail -o $cmdtools 'https://dl.google.com/android/repository/commandlinetools-win-11076708_latest.zip'
    if ($LASTEXITCODE -ne 0) { throw "cmdline-tools download failed ($LASTEXITCODE)" }
}

'DONE' | Out-File (Join-Path $dl 'download.done') -Encoding ascii
Write-Output 'Downloads complete.'
