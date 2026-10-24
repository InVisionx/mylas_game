# Build Night Shift: Not Human into an installable Android APK.
#
#   powershell -ExecutionPolicy Bypass -File tools\build_android.ps1
#
# Assumes:
#   * Godot 4.7.1 installed (set $env:GODOT if it is somewhere unusual)
#   * Export templates in %APPDATA%\Godot\export_templates\4.7.1.stable
#   * Android SDK command-line tools extracted to %LOCALAPPDATA%\Android\Sdk\cmdline-tools\latest
# The script will install the required SDK packages if sdkmanager is present.

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
Set-Location $root

$godot = $env:GODOT
if (-not $godot) {
    $godot = 'C:\Users\mattm\Desktop\godot\Godot_v4.7.1-stable_win64.exe\Godot_v4.7.1-stable_win64_console.exe'
}
if (-not (Test-Path $godot)) {
    throw "Godot console executable not found. Set `$env:GODOT to the console .exe path."
}

$sdk = Join-Path $env:LOCALAPPDATA 'Android\Sdk'
$templates = Join-Path $env:APPDATA 'Godot\export_templates\4.7.1.stable'
if (-not (Test-Path (Join-Path $templates 'android_release.apk'))) {
    Write-Warning "Export templates not found in $templates. Download Godot_v4.7.1-stable_export_templates.tpz and extract it there (see README)."
}

$sdkManager = Join-Path $sdk 'cmdline-tools\latest\bin\sdkmanager.bat'
if (Test-Path $sdkManager) {
    Write-Output 'Ensuring Android SDK packages...'
    & $sdkManager --sdk_root=$sdk 'platform-tools' 'build-tools;34.0.0' 'platforms;android-34'
} else {
    Write-Warning "sdkmanager not found at $sdkManager. Android export needs SDK command-line tools."
}

New-Item -ItemType Directory -Force -Path (Join-Path $root 'build') | Out-Null

Write-Output 'Exporting release APK...'
& $godot --headless --path $root --export-release 'Android' (Join-Path $root 'build\NightShift-NotHuman.apk')
if ($LASTEXITCODE -ne 0) {
    throw "Export failed with code $LASTEXITCODE"
}

$apk = Join-Path $root 'build\NightShift-NotHuman.apk'
if (Test-Path $apk) {
    Write-Output ("APK ready: $apk (" + [math]::Round((Get-Item $apk).Length / 1MB, 1) + " MB)")
    Write-Output 'Install on the handheld with: adb install -r build\NightShift-NotHuman.apk'
} else {
    throw 'Export reported success but no APK was produced.'
}
