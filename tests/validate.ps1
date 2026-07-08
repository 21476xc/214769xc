[CmdletBinding()]
param(
    [string]$BashPath,
    [switch]$SkipBash
)

$ErrorActionPreference = "Stop"
$repoRoot = Split-Path -Parent $PSScriptRoot

function Write-Ok {
    param([string]$Message)
    Write-Host "OK $Message" -ForegroundColor Green
}

function Write-Fail {
    param([string]$Message)
    Write-Host "FAIL $Message" -ForegroundColor Red
}

function Resolve-BashPath {
    if ($BashPath) {
        return $BashPath
    }

    $candidates = @()
    $bashCommand = Get-Command bash -ErrorAction SilentlyContinue
    if ($bashCommand) {
        $candidates += $bashCommand.Source
    }

    $gitCommand = Get-Command git -ErrorAction SilentlyContinue
    if ($gitCommand) {
        $gitRoot = Split-Path -Parent (Split-Path -Parent $gitCommand.Source)
        $candidates += Join-Path $gitRoot "bin\bash.exe"
        $candidates += Join-Path $gitRoot "usr\bin\bash.exe"
    }

    $programFiles = @($env:ProgramFiles, ${env:ProgramFiles(x86)}) | Where-Object { $_ }
    foreach ($root in $programFiles) {
        $candidates += Join-Path $root "Git\bin\bash.exe"
    }

    foreach ($candidate in ($candidates | Where-Object { $_ } | Select-Object -Unique)) {
        if (Test-Path -LiteralPath $candidate) {
            $previousPreference = $ErrorActionPreference
            $ErrorActionPreference = "Continue"
            try {
                & $candidate -c "true" *> $null
                if ($LASTEXITCODE -eq 0) {
                    return $candidate
                }
            }
            finally {
                $ErrorActionPreference = $previousPreference
            }
        }
    }

    return $null
}

$psFiles = @(
    "install.ps1",
    "scripts\install.ps1",
    "bin\jiuguan.ps1",
    "lib\jiuguan.ps1"
)

$failed = $false
foreach ($file in $psFiles) {
    $fullPath = Join-Path $repoRoot $file
    $tokens = $null
    $errors = $null
    [System.Management.Automation.Language.Parser]::ParseFile($fullPath, [ref]$tokens, [ref]$errors) | Out-Null
    if ($errors.Count -gt 0) {
        $failed = $true
        Write-Fail $file
        $errors | ForEach-Object { Write-Host "  $($_.Message)" }
    }
    else {
        Write-Ok $file
    }
}

$helpPath = Join-Path $repoRoot "bin\jiuguan.ps1"
& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $helpPath help | Out-Null
if ($LASTEXITCODE -eq 0) {
    Write-Ok "bin\jiuguan.ps1 help"
}
else {
    Write-Fail "bin\jiuguan.ps1 help"
    $failed = $true
}

if (-not $SkipBash) {
    $resolvedBash = Resolve-BashPath
    if ($resolvedBash) {
        $shFiles = @(
            "install.sh",
            "scripts/install.sh",
            "bin/jiuguan.sh",
            "lib/jiuguan.sh"
        )

        foreach ($file in $shFiles) {
            $fullPath = Join-Path $repoRoot $file
            & $resolvedBash -n $fullPath
            if ($LASTEXITCODE -eq 0) {
                Write-Ok $file
            }
            else {
                Write-Fail $file
                $failed = $true
            }
        }
    }
    else {
        Write-Host "SKIP bash syntax checks: no bash executable found" -ForegroundColor Yellow
    }
}

if ($failed) {
    exit 1
}

Write-Ok "validation complete"


