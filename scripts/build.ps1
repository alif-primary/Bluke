#Requires -Version 5.1
<#
.SYNOPSIS
    Build (and optionally install) Bluke Free on Windows.

.EXAMPLE
    .\scripts\build.ps1
    Debug APK -> app\build\outputs\apk\debug\

.EXAMPLE
    .\scripts\build.ps1 -Release -Keystore C:\keys\my-upload-key.jks
    Signed release APK -> app\build\outputs\apk\release\

.EXAMPLE
    .\scripts\build.ps1 -Install
    Builds the debug APK and installs it on the USB-connected phone.
#>
[CmdletBinding()]
param(
    [switch]$Release,
    [switch]$Install,
    [string]$Device,
    [string]$Keystore,
    [string]$StorePassword,
    [string]$KeyAlias = 'k0',
    [string]$KeyPassword
)

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot

$hasLocalProps = Test-Path (Join-Path $repoRoot 'local.properties')
if (-not $hasLocalProps -and -not $env:ANDROID_HOME -and -not $env:ANDROID_SDK_ROOT) {
    throw "Android SDK not configured. Run .\scripts\setup.ps1 once (or set ANDROID_HOME)."
}

if ($Keystore) {
    $resolved = (Resolve-Path $Keystore -ErrorAction Stop).Path
    $env:KEYSTORE_PATH = $resolved
    $env:KEY_ALIAS = $KeyAlias
    if ($StorePassword) { $env:STORE_PASSWORD = $StorePassword }
    if ($KeyPassword) { $env:KEY_PASSWORD = $KeyPassword }
    if (-not $StorePassword) {
        $secure = Read-Host "Keystore password for $resolved" -AsSecureString
        $env:STORE_PASSWORD = [Runtime.InteropServices.Marshal]::PtrToStringAuto(
            [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure))
        $env:KEY_PASSWORD = $env:STORE_PASSWORD
    }
    $Release = $true
}

if ($Install) {
    $task = 'installDebug'
} elseif ($Release) {
    $task = 'assembleRelease'
} else {
    $task = 'assembleDebug'
}

$gradlew = Join-Path $repoRoot 'gradlew.bat'
Push-Location $repoRoot
try {
    $gradleArgs = @($task, '--console=plain')
    if ($Device) { $gradleArgs += "-Pandroid.injected.device.serial=$Device" }
    Write-Host "==> gradlew $($gradleArgs -join ' ')" -ForegroundColor Cyan
    & $gradlew @gradleArgs
    if ($LASTEXITCODE -ne 0) { throw "Gradle failed with exit code $LASTEXITCODE" }
} finally {
    Pop-Location
}

$variant = if ($Release) { 'release' } else { 'debug' }
$outDir = Join-Path $repoRoot "app\build\outputs\apk\$variant"
$apk = Get-ChildItem -Path $outDir -Filter *.apk -Recurse -ErrorAction SilentlyContinue |
    Sort-Object LastWriteTime -Descending | Select-Object -First 1

if ($apk) {
    Write-Host "`nAPK: $($apk.FullName)" -ForegroundColor Green
    Write-Host ("     {0:N1} MB" -f ($apk.Length / 1MB))
} else {
    Write-Warning "Build finished but no APK was found under $outDir"
}
