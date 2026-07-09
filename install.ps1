[CmdletBinding()]
param(
    [string]$RawBaseUrl = $env:JIUGUAN_RAW_BASE_URL,
    [string]$InstallRoot = $env:JIUGUAN_HOME,
    [switch]$SkipInstall
)

$ErrorActionPreference = "Stop"

$defaultRawBaseUrl = "https://raw.githubusercontent.com/21476xc/214769xc/main"
$rawBaseFallbackUrls = @(
    "https://cdn.jsdelivr.net/gh/21476xc/214769xc@main",
    "https://fastly.jsdelivr.net/gh/21476xc/214769xc@main"
)

if (-not $RawBaseUrl) {
    $RawBaseUrl = $defaultRawBaseUrl
}

function Get-RawBaseCandidates {
    param([string]$Preferred)

    $seen = @{}
    foreach ($base in @($Preferred, $defaultRawBaseUrl) + $rawBaseFallbackUrls) {
        if (-not $base) {
            continue
        }

        if (-not $seen.ContainsKey($base)) {
            $seen[$base] = $true
            $base
        }
    }
}

function Get-RemoteInstallerContent {
    param([string]$RelativePath)

    foreach ($base in @(Get-RawBaseCandidates -Preferred $RawBaseUrl)) {
        $uri = "$base/$RelativePath"
        Write-Host "[信息] 下载 $uri"
        try {
            $response = Invoke-WebRequest -Uri $uri -UseBasicParsing -ErrorAction Stop
            $script:RawBaseUrl = $base
            return $response.Content
        }
        catch {
            Write-Host "[提醒] 下载失败，尝试备用源。"
        }
    }

    throw "所有下载源都失败了，请稍后重试或切换网络。"
}

if ($PSScriptRoot) {
    $localInstaller = Join-Path $PSScriptRoot "scripts\install.ps1"
    if (Test-Path -LiteralPath $localInstaller) {
        & $localInstaller -RawBaseUrl $RawBaseUrl -InstallRoot $InstallRoot -SkipInstall:$SkipInstall
        exit $LASTEXITCODE
    }
}

$script = Get-RemoteInstallerContent -RelativePath "scripts/install.ps1"
$tempFile = Join-Path ([System.IO.Path]::GetTempPath()) "jiuguan-install.ps1"
Set-Content -LiteralPath $tempFile -Value $script -Encoding UTF8
& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $tempFile -RawBaseUrl $RawBaseUrl -InstallRoot $InstallRoot -SkipInstall:$SkipInstall
exit $LASTEXITCODE
