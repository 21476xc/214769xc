[CmdletBinding()]
param(
    [string]$RawBaseUrl = $env:JIUGUAN_RAW_BASE_URL,
    [string]$InstallRoot = $env:JIUGUAN_HOME,
    [switch]$SkipInstall
)

$ErrorActionPreference = "Stop"

if (-not $InstallRoot) {
    $InstallRoot = Join-Path $HOME "214769SillyTavern"
}

if (-not $RawBaseUrl) {
    $RawBaseUrl = "https://raw.githubusercontent.com/21476xc/214769xc/main"
}

$script:DefaultRawBaseUrl = "https://raw.githubusercontent.com/21476xc/214769xc/main"
$script:RawBaseFallbackUrls = @(
    "https://cdn.jsdelivr.net/gh/21476xc/214769xc@main",
    "https://fastly.jsdelivr.net/gh/21476xc/214769xc@main"
)
$script:SelectedRawBaseUrl = $RawBaseUrl

function Write-InstallInfo {
    param([string]$Message)
    Write-Host "[信息] $Message"
}

function Write-InstallSuccess {
    param([string]$Message)
    Write-Host "[完成] $Message" -ForegroundColor Green
}

function Write-InstallWarn {
    param([string]$Message)
    Write-Host "[提醒] $Message" -ForegroundColor Yellow
}

function Get-InstallRawBaseCandidates {
    param([string]$Preferred)

    $seen = @{}
    foreach ($base in @($Preferred, $script:DefaultRawBaseUrl) + $script:RawBaseFallbackUrls) {
        if (-not $base) {
            continue
        }

        if (-not $seen.ContainsKey($base)) {
            $seen[$base] = $true
            $base
        }
    }
}

function Copy-OrDownloadToolFile {
    param(
        [Parameter(Mandatory = $true)][string]$RelativePath,
        [Parameter(Mandatory = $true)][string]$Destination,
        [Parameter(Mandatory = $true)][string]$RawBaseUrl
    )

    $localCandidates = @()
    if ($PSScriptRoot) {
        $localCandidates += Join-Path (Split-Path -Parent $PSScriptRoot) $RelativePath
        $localCandidates += Join-Path $PSScriptRoot $RelativePath
    }

    foreach ($candidate in $localCandidates) {
        if (Test-Path -LiteralPath $candidate) {
            Copy-Item -LiteralPath $candidate -Destination $Destination -Force
            return
        }
    }

    foreach ($base in @(Get-InstallRawBaseCandidates -Preferred $RawBaseUrl)) {
        $uri = "$base/$RelativePath"
        Write-InstallInfo "下载 $uri"
        try {
            Invoke-WebRequest -Uri $uri -UseBasicParsing -OutFile $Destination -ErrorAction Stop
            $script:SelectedRawBaseUrl = $base
            return
        }
        catch {
            Write-InstallWarn "下载失败，尝试备用源。"
        }
    }

    throw "下载 $RelativePath 失败。请检查网络后重试。"
}

$InstallRoot = [System.IO.Path]::GetFullPath($InstallRoot)
$toolRoot = Join-Path $InstallRoot ".jiuguan-tool"
$binDir = Join-Path $toolRoot "bin"
$libDir = Join-Path $toolRoot "lib"

New-Item -ItemType Directory -Force -LiteralPath $binDir | Out-Null
New-Item -ItemType Directory -Force -LiteralPath $libDir | Out-Null

Copy-OrDownloadToolFile -RelativePath "bin/jiuguan.ps1" -Destination (Join-Path $binDir "jiuguan.ps1") -RawBaseUrl $script:SelectedRawBaseUrl
Copy-OrDownloadToolFile -RelativePath "lib/jiuguan.ps1" -Destination (Join-Path $libDir "jiuguan.ps1") -RawBaseUrl $script:SelectedRawBaseUrl
Set-Content -LiteralPath (Join-Path $toolRoot "raw-base-url.txt") -Value $script:SelectedRawBaseUrl -Encoding UTF8

$cliPath = Join-Path $binDir "jiuguan.ps1"
$shimPath = Join-Path $InstallRoot "jiuguan.cmd"
$shim = @"
@echo off
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$cliPath" %*
"@
Set-Content -LiteralPath $shimPath -Value $shim -Encoding ASCII

$userPath = [Environment]::GetEnvironmentVariable("Path", "User")
$pathParts = @($userPath -split ";" | Where-Object { $_ })
if ($pathParts -notcontains $InstallRoot) {
    $newPath = (@($pathParts) + $InstallRoot) -join ";"
    [Environment]::SetEnvironmentVariable("Path", $newPath, "User")
    $env:Path = "$env:Path;$InstallRoot"
    Write-InstallInfo "已把 $InstallRoot 加入用户 PATH。新开的终端会自动生效。"
}

Write-InstallSuccess "214769SillyTavern 管理命令已安装：$shimPath"

if (-not $SkipInstall) {
    Write-InstallInfo "开始安装或修复 SillyTavern。"
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $cliPath install
    if ($LASTEXITCODE -ne 0) {
        exit $LASTEXITCODE
    }

    Write-InstallInfo "启动 SillyTavern 并显示访问地址。"
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $cliPath start
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $cliPath status

    Write-InstallInfo "进入数字控制台。"
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $cliPath menu
}

Write-InstallSuccess "全部完成。以后直接运行 jiuguan 也可以再次打开数字控制台。"
