#Requires -Version 5.1
<#
.SYNOPSIS
    Commit everything, rebase on origin, push.
.EXAMPLE
    .\scripts\sync.ps1 "describe change"
#>
[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [string]$Message
)

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
if (-not $Message) { $Message = "update $(Get-Date -Format 'yyyy-MM-dd HH:mm')" }

Push-Location $repoRoot
try {
    git add -A
    git diff --cached --quiet
    if ($LASTEXITCODE -eq 0) {
        Write-Host 'nothing to commit'
    } else {
        git commit -m $Message
        if ($LASTEXITCODE -ne 0) { throw 'commit failed' }
    }

    git pull --rebase
    if ($LASTEXITCODE -ne 0) { throw 'pull --rebase failed (resolve conflicts, then git rebase --continue)' }

    git push
    if ($LASTEXITCODE -ne 0) { throw 'push failed' }

    git status -sb | Select-Object -First 1
} finally {
    Pop-Location
}
