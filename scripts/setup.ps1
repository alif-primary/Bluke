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

.PARAMETER SdkRoot
    Where to install the Android SDK. Defaults to %LOCALAPPDATA%\Android\Sdk.

.PARAMETER SkipJdk
    Do not look for or install a JDK.

.PARAMETER SkipSdk
    Do not download or install the Android SDK.

.PARAMETER NoBuild
    Stop after setup; do not run the debug build.

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

# Windows PowerShell 5.1: native tools write progress/warnings to stderr, and
# merging that under $ErrorActionPreference='Stop' turns it into a terminating
# "NativeCommandError". Every native call goes through the helpers below, which
# relax that preference for the duration of the call.
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
try { [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12 } catch { }

$repoRoot = Split-Path -Parent $PSScriptRoot
$script:Answers = ((1..80 | ForEach-Object { 'y' }) -join "`n") + "`n"
$script:StepName = 'start'

function Step([string]$text) {
    $script:StepName = $text
    Write-Host ''
    Write-Host "==> $text" -ForegroundColor Cyan
}
function Info([string]$text) { Write-Host "    $text" -ForegroundColor DarkGray }
function Warn([string]$text) { Write-Host "    !  $text" -ForegroundColor Yellow }

function Invoke-Native {
    <# Runs a native command, captures stdout+stderr as text, never throws on stderr. #>
    param(
        [Parameter(Mandatory)][string]$FilePath,
        [string[]]$ArgumentList = @(),
        [string]$Stdin,
        [switch]$PassThru
    )
    $old = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        if ($PSBoundParameters.ContainsKey('Stdin')) {
            $text = ($Stdin | & $FilePath @ArgumentList 2>&1 | ForEach-Object { "$_" }) -join "`n"
        } else {
            $text = (& $FilePath @ArgumentList 2>&1 | ForEach-Object { "$_" }) -join "`n"
        }
        $code = $LASTEXITCODE
    } finally {
        $ErrorActionPreference = $old
    }
    if ($PassThru) { Write-Host $text }
    return [pscustomobject]@{ Output = $text; ExitCode = $code }
}

function Get-JavaMajor([string]$javaExe) {
    $r = Invoke-Native -FilePath $javaExe -ArgumentList @('-version')
    if ($r.Output -match '"(?<v>\d+)') { return [int]$Matches['v'] }
    return 0
}

function Find-Jdk {
    $candidates = @()
    if ($env:JAVA_HOME) { $candidates += $env:JAVA_HOME }
    $cmd = Get-Command java -ErrorAction SilentlyContinue
    if ($cmd) { $candidates += (Split-Path -Parent (Split-Path -Parent $cmd.Source)) }
    foreach ($root in @("$env:ProgramFiles\Microsoft", "$env:ProgramFiles\Eclipse Adoptium",
            "$env:ProgramFiles\Java", "${env:ProgramFiles(x86)}\Microsoft")) {
        if ($root -and (Test-Path $root)) {
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
    $pinned = 'https://dl.google.com/android/repository/commandlinetools-win-16111833_latest.zip'
    try {
        $r = Invoke-Native -FilePath 'curl.exe' -ArgumentList @('-fsSL', '--max-time', '60',
            'https://dl.google.com/android/repository/repository2-3.xml')
        if ($r.ExitCode -eq 0 -and $r.Output) {
            $m = [regex]::Match($r.Output, "commandlinetools-$Os[^""]*?_latest\.zip")
            if ($m.Success) { return 'https://dl.google.com/android/repository/' + $m.Value }
        }
    } catch { }
    Warn 'could not read the SDK package index, using the pinned build'
    return $pinned
}

function Expand-Zip([string]$ZipPath, [string]$Destination) {
    Add-Type -AssemblyName System.IO.Compression.FileSystem -ErrorAction SilentlyContinue
    [System.IO.Compression.ZipFile]::ExtractToDirectory($ZipPath, $Destination)
}

function Write-LocalProperties([string]$SdkPath) {
    $file = Join-Path $repoRoot 'local.properties'
    "sdk.dir=$($SdkPath -replace '\\', '/')" | Set-Content -Path $file -Encoding ASCII
    Info "wrote $file"
}

function Invoke-SdkManager {
    param(
        [Parameter(Mandatory)][string]$SdkManager,
        [string[]]$Arguments = @(),
        [string]$Stdin
    )
    $argv = @("--sdk_root=$SdkRoot") + $Arguments
    if ($PSBoundParameters.ContainsKey('Stdin')) {
        return (Invoke-Native -FilePath $SdkManager -ArgumentList $argv -Stdin $Stdin)
    }
    return (Invoke-Native -FilePath $SdkManager -ArgumentList $argv)
}

# ------------------------------------------------------------------ main ----
try {
    # ---------------------------------------------------------------- JDK ----
    Step 'Java 17'
    if ($SkipJdk) {
        Info 'skipped (-SkipJdk)'
    } else {
        $jdkHome = Find-Jdk
        if ($jdkHome) {
            Info "found $jdkHome"
        } else {
            $winget = Get-Command winget -ErrorAction SilentlyContinue
            if (-not $winget) {
                Warn 'no JDK 17 and no winget'
                throw "Install 'Microsoft OpenJDK 17' from https://learn.microsoft.com/java/openjdk/download, open a new terminal, and run this script again."
            }
            foreach ($id in @('Microsoft.OpenJDK.17', 'EclipseAdoptium.Temurin.17.JDK')) {
                Info "winget install $id"
                $r = Invoke-Native -FilePath $winget.Source -ArgumentList @(
                    'install', '--id', $id, '--exact', '--silent',
                    '--accept-source-agreements', '--accept-package-agreements',
                    '--disable-interactivity')
                $jdkHome = Find-Jdk
                if ($jdkHome) { break }
                if ($r.Output -match 'admin|elevat|0x8a1500') {
                    Warn "$id needs an administrator prompt"
                }
            }
        }

        if (-not $jdkHome) {
            throw @"
Could not install a JDK automatically.

  1. Install 'Microsoft OpenJDK 17' from
     https://learn.microsoft.com/java/openjdk/download
     (or run: winget install Microsoft.OpenJDK.17)
  2. Close this window, open a new PowerShell, and run setup again.
"@
        }

        $env:JAVA_HOME = $jdkHome
        $env:PATH = (Join-Path $jdkHome 'bin') + ';' + $env:PATH
        [Environment]::SetEnvironmentVariable('JAVA_HOME', $jdkHome, 'User')
        Info "JAVA_HOME=$jdkHome"
    }

    # ------------------------------------------------------------ Android ----
    if ($SkipSdk) {
        Step 'Android SDK'
        Info 'skipped (-SkipSdk)'
    } else {
        Step "Android SDK ($SdkRoot)"
        $sdkManager = Join-Path $SdkRoot 'cmdline-tools\latest\bin\sdkmanager.bat'

        if (-not (Test-Path $sdkManager)) {
            $url = Get-CommandLineToolsUrl -Os win
            $zip = Join-Path $env:TEMP 'cmdline-tools.zip'
            Info "downloading $url"
            $downloaded = $false
            try {
                $r = Invoke-Native -FilePath 'curl.exe' -ArgumentList @('-fL', '--retry', '3', '-o', $zip, $url)
                $downloaded = ($r.ExitCode -eq 0) -and (Test-Path $zip)
            } catch {
                Warn 'curl.exe not available'
            }
            if (-not $downloaded) {
                Warn 'falling back to Invoke-WebRequest'
                Invoke-WebRequest -Uri $url -OutFile $zip -UseBasicParsing
            }
            Info ("downloaded {0:N0} MB" -f ((Get-Item $zip).Length / 1MB))

            $staging = Join-Path $env:TEMP ("cmdtools-" + [guid]::NewGuid().ToString('N'))
            Info 'extracting'
            Expand-Zip -ZipPath $zip -Destination $staging

            $target = Join-Path $SdkRoot 'cmdline-tools\latest'
            if (Test-Path $target) { Remove-Item -Recurse -Force $target }
            New-Item -ItemType Directory -Force -Path (Split-Path -Parent $target) | Out-Null
            Move-Item (Join-Path $staging 'cmdline-tools') $target
            Remove-Item -Recurse -Force $staging, $zip -ErrorAction SilentlyContinue
            Info "installed $target"
        } else {
            Info 'command-line tools already present'
        }

        Step 'Accepting SDK licences'
        $r = Invoke-SdkManager -SdkManager $sdkManager -Arguments @('--licenses') -Stdin $script:Answers
        if ($r.ExitCode -ne 0) { Warn "sdkmanager --licenses exited with $($r.ExitCode)" }
        Info 'licences accepted'

        Step 'Installing SDK packages'
        foreach ($pkg in @('platform-tools', 'platforms;android-36.1', 'build-tools;36.1.0')) {
            $r = Invoke-SdkManager -SdkManager $sdkManager -Arguments @($pkg)
            if ($r.ExitCode -eq 0) { Info "installed $pkg" }
            else { Warn "$pkg not installed (Gradle can fetch it on first build)" }
        }

        [Environment]::SetEnvironmentVariable('ANDROID_HOME', $SdkRoot, 'User')
        [Environment]::SetEnvironmentVariable('ANDROID_SDK_ROOT', $SdkRoot, 'User')
        $env:ANDROID_HOME = $SdkRoot
        $env:ANDROID_SDK_ROOT = $SdkRoot
        Write-LocalProperties -SdkPath $SdkRoot
    }

    # --------------------------------------------------------------- build ----
    if (-not $NoBuild) {
        Step 'Building debug APK'
        & (Join-Path $PSScriptRoot 'build.ps1')
        if ($LASTEXITCODE -ne 0) { throw "build.ps1 failed with exit code $LASTEXITCODE" }
    }
} catch {
    Write-Host ''
    Write-Host "Setup failed during: $script:StepName" -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Red
    Write-Host ''
    Write-Host 'Nothing was changed outside your user profile. Fix the above and re-run:' -ForegroundColor Yellow
    Write-Host '  .\scripts\setup.ps1 -SkipJdk -SkipSdk   # skip steps that already worked' -ForegroundColor Yellow
    exit 1
}

Write-Host ''
Write-Host 'Setup finished.' -ForegroundColor Green
Write-Host '  Build:   .\scripts\build.ps1            (debug)'
Write-Host '           .\scripts\build.ps1 -Release -Keystore C:\keys\my-upload-key.jks'
Write-Host '  Install: .\scripts\build.ps1 -Install   (phone on USB, debugging on)'
Write-Host '  Docs:    docs\PC-SETUP.md'
