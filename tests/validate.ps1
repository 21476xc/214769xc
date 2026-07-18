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

$readmePath = Join-Path $repoRoot "README.md"
$readme = [System.IO.File]::ReadAllText($readmePath, [System.Text.Encoding]::UTF8)
if ($readme -match 'irm\s+https://cdn\.jsdelivr\.net/.+\|\s*iex') {
    Write-Fail "README Windows installer must not pipe jsDelivr content into iex"
    $failed = $true
}
else {
    Write-Ok "README Windows installer downloads to a file"
}

if ($readme -match 'cdn\.jsdelivr\.net/gh/21476xc/214769xc@main/scripts/install\.ps1') {
    Write-Fail "README Windows installer must use an immutable bootstrap revision"
    $failed = $true
}
else {
    Write-Ok "README Windows installer uses an immutable bootstrap revision"
}

if ($readme -match 'cdn\.jsdelivr\.net/gh/21476xc/214769xc@main/install\.sh') {
    Write-Fail "README Bash installers must use an immutable bootstrap revision"
    $failed = $true
}
else {
    Write-Ok "README Bash installers use an immutable bootstrap revision"
}

$rootInstaller = [System.IO.File]::ReadAllText((Join-Path $repoRoot "install.ps1"), [System.Text.Encoding]::UTF8)
if ($rootInstaller -notmatch 'Invoke-WebRequest.+-OutFile\s+\$Destination') {
    Write-Fail "install.ps1 must preserve downloaded script bytes"
    $failed = $true
}
else {
    Write-Ok "install.ps1 preserves downloaded script bytes"
}

$bootstrapFiles = @("install.ps1", "scripts\install.ps1", "install.sh", "scripts\install.sh")
foreach ($bootstrapFile in $bootstrapFiles) {
    $bootstrapText = [System.IO.File]::ReadAllText((Join-Path $repoRoot $bootstrapFile), [System.Text.Encoding]::UTF8)
    if ($bootstrapText -notmatch '214769xc@v0\.2\.0') {
        Write-Fail "$bootstrapFile must download a stable release"
        $failed = $true
    }
    else {
        Write-Ok "$bootstrapFile stable release source"
    }
}

$windowsLibrary = [System.IO.File]::ReadAllText((Join-Path $repoRoot "lib\jiuguan.ps1"), [System.Text.Encoding]::UTF8)
if ($windowsLibrary -notmatch 'ExpectedCommit' -or
    $windowsLibrary -notmatch 'SillyTavern\)\.download' -or
    $windowsLibrary -notmatch '上次下载中断') {
    Write-Fail "Windows installer must verify mirrors and recover interrupted clones"
    $failed = $true
}
else {
    Write-Ok "Windows verified mirror and interrupted clone recovery"
}

$bashLibrary = [System.IO.File]::ReadAllText((Join-Path $repoRoot "lib\jiuguan.sh"), [System.Text.Encoding]::UTF8)
if ($bashLibrary -notmatch 'official_commit' -or
    $bashLibrary -notmatch '\$\{JG_ST\}\.download' -or
    $bashLibrary -notmatch '上次下载中断') {
    Write-Fail "Bash installer must verify mirrors and recover interrupted clones"
    $failed = $true
}
else {
    Write-Ok "Bash verified mirror and interrupted clone recovery"
}

$unsupportedNewItemLiteralPath = Select-String -Path $psFiles.ForEach({ Join-Path $repoRoot $_ }) -Pattern '\bNew-Item\b.*-LiteralPath'
if ($unsupportedNewItemLiteralPath) {
    Write-Fail "New-Item -LiteralPath is not supported by Windows PowerShell 5.1"
    $unsupportedNewItemLiteralPath | ForEach-Object { Write-Host "  $($_.Path):$($_.LineNumber)" }
    $failed = $true
}
else {
    Write-Ok "Windows PowerShell 5.1 New-Item parameters"
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


