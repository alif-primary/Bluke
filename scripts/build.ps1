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
$ProgressPreference = 'SilentlyContinue'
$script:StepName = 'start'

function Step([string]$text) {
    $script:StepName = $text
    Write-Host ''
    Write-Host "==> $text" -ForegroundColor Cyan
}
function Info([string]$text) { Write-Host "    $text" -ForegroundColor DarkGray }

function Invoke-Native {
    <# Streams native output to the host and returns only the exit code.
       Native tools write to stderr; merging that under EAP=Stop throws
       NativeCommandError, so relax the preference for the call itself. #>
    param([Parameter(Mandatory)][string]$FilePath, [string[]]$ArgumentList = @())
    $old = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        & $FilePath @ArgumentList 2>&1 | ForEach-Object { Write-Host "$_" }
        return $LASTEXITCODE
    } finally {
        $ErrorActionPreference = $old
    }
}

$repoRoot = Split-Path -Parent $PSScriptRoot

try {
    Step 'Checking toolchain'
    if (-not (Test-Path (Join-Path $repoRoot 'local.properties')) -and
        -not $env:ANDROID_HOME -and -not $env:ANDROID_SDK_ROOT) {
        throw 'Android SDK not configured. Run .\scripts\setup.ps1 once (or set ANDROID_HOME).'
    }
    Info "repo: $repoRoot"

    if ($Keystore) {
        $resolved = (Resolve-Path $Keystore -ErrorAction Stop).Path
        $env:KEYSTORE_PATH = $resolved
        $env:KEY_ALIAS = $KeyAlias
        if (-not $StorePassword) {
            $secure = Read-Host "Keystore password for $resolved" -AsSecureString
            $StorePassword = [Runtime.InteropServices.Marshal]::PtrToStringAuto(
                [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure))
        }
        $env:STORE_PASSWORD = $StorePassword
        $env:KEY_PASSWORD = if ($KeyPassword) { $KeyPassword } else { $StorePassword }
        $Release = $true
        Info "signing with $resolved"
    }

    if ($Install) { $task = 'installDebug' }
    elseif ($Release) { $task = 'assembleRelease' }
    else { $task = 'assembleDebug' }

    Step "gradlew $task"
    $gradlew = Join-Path $repoRoot 'gradlew.bat'
    if (-not (Test-Path $gradlew)) { throw "gradlew.bat missing at $gradlew" }

    Push-Location $repoRoot
    try {
        $gradleArgs = @($task, '--console=plain')
        if ($Device) { $gradleArgs += "-Pandroid.injected.device.serial=$Device" }
        $code = Invoke-Native -FilePath $gradlew -ArgumentList $gradleArgs
    } finally {
        Pop-Location
    }
    if ($code -ne 0) { throw "Gradle failed with exit code $code" }

    Step 'Locating APK'
    $variant = if ($Release) { 'release' } else { 'debug' }
    $outDir = Join-Path $repoRoot "app\build\outputs\apk\$variant"
    $apk = Get-ChildItem -Path $outDir -Filter *.apk -Recurse -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime -Descending | Select-Object -First 1

    if (-not $apk) { throw "No APK under $outDir" }

    Write-Host ''
    Write-Host "APK: $($apk.FullName)" -ForegroundColor Green
    Write-Host ("     {0:N1} MB" -f ($apk.Length / 1MB))
} catch {
    Write-Host ''
    Write-Host "Build failed during: $script:StepName" -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Red
    exit 1
}
