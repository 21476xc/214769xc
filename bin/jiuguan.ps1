[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [string]$Command = "menu",

    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$Rest = @()
)

$ErrorActionPreference = "Stop"

$toolRoot = Split-Path -Parent $PSScriptRoot
$libPath = Join-Path $toolRoot "lib\jiuguan.ps1"
if (-not (Test-Path -LiteralPath $libPath)) {
    $repoLibPath = Join-Path (Split-Path -Parent $PSScriptRoot) "..\lib\jiuguan.ps1"
    if (Test-Path -LiteralPath $repoLibPath) {
        $libPath = $repoLibPath
    }
}

. $libPath

try {
    switch ($Command.ToLowerInvariant()) {
        "install" { Install-JgDeployment }
        "update" { Update-JgDeployment }
        "start" { Start-JgSillyTavern }
        "stop" { Stop-JgSillyTavern }
        "restart" { Restart-JgSillyTavern }
        "status" { Show-JgStatus }
        "logs" {
            $lines = 120
            if ($Rest.Count -gt 0 -and $Rest[0] -match "^\d+$") {
                $lines = [int]$Rest[0]
            }

            Show-JgLogs -Lines $lines
        }
        "backup" { New-JgBackup }
        "restore" {
            $backupPath = if ($Rest.Count -gt 0) { $Rest[0] } else { $null }
            Restore-JgBackup -BackupPath $backupPath
        }
        "uninstall" {
            $deleteData = $Rest -contains "--delete-data"
            Uninstall-JgDeployment -DeleteData:$deleteData
        }
        "menu" { Show-JgMenu }
        "help" { Show-JgHelp }
        "--help" { Show-JgHelp }
        "-h" { Show-JgHelp }
        default {
            Write-JgWarn "未知命令：$Command"
            Show-JgHelp
            exit 2
        }
    }
}
catch {
    Write-JgError $_.Exception.Message
    exit 1
}
