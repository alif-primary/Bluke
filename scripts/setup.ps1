#Requires -Version 5.1
<#
.SYNOPSIS
    One-shot setup for building Bluke Free on Windows.

.DESCRIPTION
    Installs a JDK 17 (winget) and the Android command-line tools, accepts the
    SDK licences, installs the SDK packages this project needs, writes
    local.properties, and then builds a debug APK.

    Nothing is installed system-wide except the JDK; the SDK lives in
    %LOCALAPPDATA%\Android\Sdk by default.

.EXAMPLE
    .\scripts\setup.ps1

.EXAMPLE
    .\scripts\setup.ps1 -SdkRoot D:\Android\Sdk -NoBuild
#>
[CmdletBinding()]
param(
    [string]$SdkRoot = (Join-Path $env:LOCALAPPDATA 'Android\Sdk'),
    [switch]$SkipJdk,
    [switch]$SkipSdk,
    [switch]$NoBuild
)

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
$script:Answers = (1..80 | ForEach-Object { 'y' }) -join "`n"

function Step([string]$text) { Write-Host "`n==> $text" -ForegroundColor Cyan }
function Info([string]$text) { Write-Host "    $text" -ForegroundColor DarkGray }
function Warn([string]$text) { Write-Host "    !  $text" -ForegroundColor Yellow }

function Get-JavaMajor([string]$javaExe) {
    try {
        $line = (& $javaExe -version 2>&1 | Select-Object -First 1) -join ''
        if ($line -match '"(?<v>\d+)') { return [int]$Matches['v'] }
    } catch { }
    return 0
}

function Find-Jdk {
    $candidates = @()
    if ($env:JAVA_HOME) { $candidates += $env:JAVA_HOME }
    $cmd = Get-Command java -ErrorAction SilentlyContinue
    if ($cmd) { $candidates += (Split-Path -Parent (Split-Path -Parent $cmd.Source)) }
    foreach ($root in @("$env:ProgramFiles\Microsoft", "$env:ProgramFiles\Eclipse Adoptium",
            "$env:ProgramFiles\Java", "${env:ProgramFiles(x86)}\Microsoft")) {
        if (Test-Path $root) {
            $candidates += (Get-ChildItem $root -Directory -ErrorAction SilentlyContinue |
                Where-Object { $_.Name -match 'jdk-17|jdk17' }).FullName
        }
    }
    foreach ($c in $candidates) {
        if (-not $c) { continue }
        $exe = Join-Path $c 'bin\java.exe'
        if ((Test-Path $exe) -and (Get-JavaMajor $exe) -ge 17) { return $c }
    }
    return $null
}

function Get-CommandLineToolsUrl {
    param([ValidateSet('win', 'linux', 'mac_arm64', 'mac_x86_64')][string]$Os = 'win')
    try {
        $xml = (Invoke-WebRequest 'https://dl.google.com/android/repository/repository2-3.xml' `
                -UseBasicParsing -TimeoutSec 60).Content
        $m = [regex]::Match($xml, "commandlinetools-$Os[^""]*?_latest\.zip")
        if ($m.Success) { return 'https://dl.google.com/android/repository/' + $m.Value }
    } catch {
        Warn "could not read the SDK package index, using the pinned build"
    }
    return 'https://dl.google.com/android/repository/commandlinetools-win-16111833_latest.zip'
}

# ---------------------------------------------------------------- JDK 17 ----
Step 'Java 17'
$jdkHome = $null
if (-not $SkipJdk) {
    $jdkHome = Find-Jdk
    if ($jdkHome) {
        Info "found $jdkHome"
    } else {
        $winget = Get-Command winget -ErrorAction SilentlyContinue
        if (-not $winget) {
            throw "No JDK 17 found and winget is unavailable. Install 'Microsoft OpenJDK 17' from https://learn.microsoft.com/java/openjdk/download and re-run."
        }
        foreach ($id in @('Microsoft.OpenJDK.17', 'EclipseAdoptium.Temurin.17.JDK')) {
            Info "winget install $id"
            & winget install --id $id --exact --silent --accept-source-agreements --accept-package-agreements 2>&1 |
                Out-Null
            $jdkHome = Find-Jdk
            if ($jdkHome) { break }
        }
    }
    if (-not $jdkHome) {
        throw 'JDK installation did not produce a usable java.exe. Open a new terminal and re-run, or install the JDK manually.'
    }
    $env:JAVA_HOME = $jdkHome
    $env:PATH = (Join-Path $jdkHome 'bin') + ';' + $env:PATH
    [Environment]::SetEnvironmentVariable('JAVA_HOME', $jdkHome, 'User')
    Info "JAVA_HOME=$jdkHome"
} else {
    Info 'skipped'
}

# ---------------------------------------------------------- Android SDK -----
if (-not $SkipSdk) {
    Step "Android SDK ($SdkRoot)"
    $sdkManager = Join-Path $SdkRoot 'cmdline-tools\latest\bin\sdkmanager.bat'

    if (-not (Test-Path $sdkManager)) {
        $url = Get-CommandLineToolsUrl -Os win
        Info "downloading $url"
        $zip = Join-Path $env:TEMP 'cmdline-tools.zip'
        Invoke-WebRequest -Uri $url -OutFile $zip -UseBasicParsing

        $staging = Join-Path $env:TEMP ("cmdtools-" + [guid]::NewGuid().ToString('N'))
        Info 'extracting'
        Expand-Archive -Path $zip -DestinationPath $staging -Force

        $target = Join-Path $SdkRoot 'cmdline-tools\latest'
        if (Test-Path $target) { Remove-Item -Recurse -Force $target }
        New-Item -ItemType Directory -Force -Path (Split-Path -Parent $target) | Out-Null
        Move-Item (Join-Path $staging 'cmdline-tools') $target
        Remove-Item -Recurse -Force $staging, $zip
        Info "installed $target"
    } else {
        Info 'command-line tools already present'
    }

    Step 'Accepting SDK licences'
    $script:Answers | & $sdkManager "--sdk_root=$SdkRoot" --licenses 2>&1 | Out-Null
    Info 'licences accepted'

    Step 'Installing SDK packages'
    foreach ($pkg in @('platform-tools', 'platforms;android-36.1', 'build-tools;36.1.0')) {
        & $sdkManager "--sdk_root=$SdkRoot" $pkg 2>&1 | Out-Null
        if ($LASTEXITCODE -eq 0) { Info "installed $pkg" }
        else { Warn "$pkg not installed (Gradle can fetch it on first build)" }
    }

    [Environment]::SetEnvironmentVariable('ANDROID_HOME', $SdkRoot, 'User')
    [Environment]::SetEnvironmentVariable('ANDROID_SDK_ROOT', $SdkRoot, 'User')
    $env:ANDROID_HOME = $SdkRoot
    $env:ANDROID_SDK_ROOT = $SdkRoot

    $localProps = Join-Path $repoRoot 'local.properties'
    "sdk.dir=$($SdkRoot -replace '\\', '/')" | Set-Content -Path $localProps -Encoding ASCII
    Info "wrote $localProps"
} else {
    Step 'Android SDK'
    Info 'skipped'
}

# --------------------------------------------------------------- build -----
if (-not $NoBuild) {
    Step 'Building debug APK'
    & (Join-Path $PSScriptRoot 'build.ps1')
}

Write-Host "`nSetup finished." -ForegroundColor Green
Write-Host "  Build:   .\scripts\build.ps1            (debug)"
Write-Host "           .\scripts\build.ps1 -Release   (signed, needs -Keystore)"
Write-Host "  Install: .\scripts\build.ps1 -Install   (phone on USB, debugging on)"
Write-Host "  Docs:    docs\PC-SETUP.md"
