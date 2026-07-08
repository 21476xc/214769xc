[CmdletBinding()]
param(
    [string]$RawBaseUrl = $env:JIUGUAN_RAW_BASE_URL,
    [string]$InstallRoot = $env:JIUGUAN_HOME,
    [switch]$SkipInstall
)

$ErrorActionPreference = "Stop"

if (-not $RawBaseUrl) {
    $RawBaseUrl = "https://raw.githubusercontent.com/21476xc/214769xc/main"
}

if ($PSScriptRoot) {
    $localInstaller = Join-Path $PSScriptRoot "scripts\install.ps1"
    if (Test-Path -LiteralPath $localInstaller) {
        & $localInstaller -RawBaseUrl $RawBaseUrl -InstallRoot $InstallRoot -SkipInstall:$SkipInstall
        exit $LASTEXITCODE
    }
}

$remoteInstaller = "$RawBaseUrl/scripts/install.ps1"
$script = (Invoke-WebRequest -Uri $remoteInstaller -UseBasicParsing -ErrorAction Stop).Content
$tempFile = Join-Path ([System.IO.Path]::GetTempPath()) "jiuguan-install.ps1"
Set-Content -LiteralPath $tempFile -Value $script -Encoding UTF8
& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $tempFile -RawBaseUrl $RawBaseUrl -InstallRoot $InstallRoot -SkipInstall:$SkipInstall
exit $LASTEXITCODE
