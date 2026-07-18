$script:JiuguanVersion = "0.1.0"
$script:SillyTavernRepoDefault = "https://github.com/SillyTavern/SillyTavern.git"
$script:NpmOfficialRegistry = "https://registry.npmjs.org/"
$script:NpmMirrorRegistry = "https://registry.npmmirror.com"
$script:ToolRawBaseDefault = "https://raw.githubusercontent.com/21476xc/214769xc/main"
$script:ToolRawBaseFallbacks = @(
    "https://cdn.jsdelivr.net/gh/21476xc/214769xc@main",
    "https://fastly.jsdelivr.net/gh/21476xc/214769xc@main"
)

function Write-JgInfo {
    param([string]$Message)
    Write-Host "[信息] $Message"
}

function Write-JgSuccess {
    param([string]$Message)
    Write-Host "[完成] $Message" -ForegroundColor Green
}

function Write-JgWarn {
    param([string]$Message)
    Write-Host "[提醒] $Message" -ForegroundColor Yellow
}

function Write-JgError {
    param([string]$Message)
    Write-Host "[错误] $Message" -ForegroundColor Red
}

function Get-JgRoot {
    if ($env:JIUGUAN_HOME) {
        return [System.IO.Path]::GetFullPath($env:JIUGUAN_HOME)
    }

    return (Join-Path $HOME "214769SillyTavern")
}

function Get-JgPaths {
    $root = Get-JgRoot
    $tool = Join-Path $root ".jiuguan-tool"
    $state = Join-Path $root ".state"
    $logs = Join-Path $root "logs"
    $backups = Join-Path $root "backups"

    [pscustomobject]@{
        Root = $root
        Tool = $tool
        Bin = Join-Path $tool "bin"
        Lib = Join-Path $tool "lib"
        SillyTavern = Join-Path $root "SillyTavern"
        State = $state
        Logs = $logs
        Backups = $backups
        PidFile = Join-Path $state "sillytavern.pid"
        MainLog = Join-Path $logs "sillytavern.log"
        RawBaseFile = Join-Path $tool "raw-base-url.txt"
        ShimCmd = Join-Path $root "jiuguan.cmd"
    }
}

function Initialize-JgDirectories {
    $paths = Get-JgPaths
    foreach ($dir in @($paths.Root, $paths.Tool, $paths.Bin, $paths.Lib, $paths.State, $paths.Logs, $paths.Backups)) {
        New-Item -ItemType Directory -Force -Path $dir | Out-Null
    }

    return $paths
}

function Test-JgCommand {
    param([string]$Name)
    return [bool](Get-Command $Name -ErrorAction SilentlyContinue)
}

function Invoke-JgExternal {
    param(
        [Parameter(Mandatory = $true)][string]$FilePath,
        [string[]]$Arguments = @(),
        [string]$Step = $FilePath
    )

    & $FilePath @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw "$Step 失败。你可以稍后重试，或把上面的错误信息复制给维护者。"
    }
}

function Refresh-JgPath {
    $machinePath = [Environment]::GetEnvironmentVariable("Path", "Machine")
    $userPath = [Environment]::GetEnvironmentVariable("Path", "User")
    $env:Path = @($machinePath, $userPath) -join ";"
}

function Install-JgWindowsPackage {
    param(
        [Parameter(Mandatory = $true)][string]$DisplayName,
        [Parameter(Mandatory = $true)][string]$WingetId,
        [Parameter(Mandatory = $true)][string]$ManualUrl
    )

    if (-not (Test-JgCommand "winget")) {
        throw "缺少 $DisplayName，且当前系统没有 winget。请手动安装：$ManualUrl"
    }

    Write-JgInfo "正在通过 winget 安装 $DisplayName。"
    & winget install --id $WingetId -e --source winget --accept-package-agreements --accept-source-agreements
    if ($LASTEXITCODE -ne 0) {
        Write-JgWarn "winget install 未完成，尝试 winget upgrade。"
        & winget upgrade --id $WingetId -e --source winget --accept-package-agreements --accept-source-agreements
        if ($LASTEXITCODE -ne 0) {
            throw "winget 安装 $DisplayName 失败。请手动安装：$ManualUrl"
        }
    }

    Refresh-JgPath
}

function Get-JgNodeVersionText {
    if (-not (Test-JgCommand "node")) {
        throw "没有找到 Node.js。"
    }

    $output = (& node --version 2>&1)
    if ($LASTEXITCODE -ne 0) {
        throw "Node.js 已安装但无法运行：$output"
    }

    return (($output | Select-Object -First 1) -replace "^v", "").Trim()
}

function Test-JgNode18 {
    try {
        $nodeVersionText = Get-JgNodeVersionText
        $nodeMajor = [int]($nodeVersionText.Split(".")[0])
        return ($nodeMajor -ge 18)
    }
    catch {
        return $false
    }
}

function Ensure-JgDependencies {
    Write-JgInfo "检查 Git 和 Node.js。"

    if (-not (Test-JgCommand "git")) {
        Install-JgWindowsPackage -DisplayName "Git" -WingetId "Git.Git" -ManualUrl "https://git-scm.com/download/win"
    }

    if (-not (Test-JgCommand "node")) {
        Install-JgWindowsPackage -DisplayName "Node.js LTS" -WingetId "OpenJS.NodeJS.LTS" -ManualUrl "https://nodejs.org/"
    }

    if (-not (Test-JgNode18)) {
        $nodeVersionText = "不可用"
        try {
            $nodeVersionText = Get-JgNodeVersionText
        }
        catch {
            Write-JgWarn $_.Exception.Message
        }
        Write-JgWarn "当前 Node.js 是 v$nodeVersionText，SillyTavern 建议使用 Node.js 18 或更新版本。"
        Install-JgWindowsPackage -DisplayName "Node.js LTS" -WingetId "OpenJS.NodeJS.LTS" -ManualUrl "https://nodejs.org/"
    }

    Refresh-JgPath
    if (-not (Test-JgNode18)) {
        throw "Node.js 安装后仍不是 18 或更新版本。请重新打开 PowerShell 后运行：jiuguan install"
    }

    if (-not (Test-JgCommand "npm")) {
        Refresh-JgPath
    }

    if (-not (Test-JgCommand "npm")) {
        throw "没有找到 npm。请重新打开 PowerShell 后运行：jiuguan install"
    }

    Write-JgSuccess "依赖检查完成。"
}

function Test-JgUrl {
    param([string]$Uri)

    try {
        Invoke-WebRequest -Uri $Uri -UseBasicParsing -TimeoutSec 8 -ErrorAction Stop | Out-Null
        return $true
    }
    catch {
        return $false
    }
}

function Get-JgRawBaseCandidates {
    param([string]$Preferred)

    $seen = @{}
    foreach ($base in @($Preferred, $script:ToolRawBaseDefault) + $script:ToolRawBaseFallbacks) {
        if (-not $base) {
            continue
        }

        if (-not $seen.ContainsKey($base)) {
            $seen[$base] = $true
            $base
        }
    }
}

function Invoke-JgDownloadToolFile {
    param(
        [Parameter(Mandatory = $true)][string]$RelativePath,
        [Parameter(Mandatory = $true)][string]$Destination,
        [string]$PreferredRawBase
    )

    foreach ($base in @(Get-JgRawBaseCandidates -Preferred $PreferredRawBase)) {
        $uri = "$base/$RelativePath"
        Write-JgInfo "下载 $uri"
        try {
            Invoke-WebRequest -Uri $uri -UseBasicParsing -OutFile $Destination -ErrorAction Stop
            return $base
        }
        catch {
            Write-JgWarn "下载失败，尝试备用源。"
        }
    }

    throw "下载 $RelativePath 失败。请检查网络后重试。"
}

function Get-JgNpmRegistryArgs {
    if ($env:JIUGUAN_NPM_REGISTRY) {
        Write-JgInfo "使用自定义 npm registry：$env:JIUGUAN_NPM_REGISTRY"
        return @("--registry", $env:JIUGUAN_NPM_REGISTRY)
    }

    & npm ping --registry $script:NpmOfficialRegistry | Out-Null
    if ($LASTEXITCODE -eq 0) {
        return @()
    }

    Write-JgWarn "npm 官方源暂时不可用，改用 npmmirror。"
    return @("--registry", $script:NpmMirrorRegistry)
}

function Get-JgSillyTavernRepoCandidates {
    $repos = @()
    if ($env:JIUGUAN_SILLYTAVERN_REPO) {
        $repos += $env:JIUGUAN_SILLYTAVERN_REPO
    }

    $repos += $script:SillyTavernRepoDefault
    return $repos | Select-Object -Unique
}

function Assert-JgSillyTavernInstalled {
    $paths = Get-JgPaths
    $packageJson = Join-Path $paths.SillyTavern "package.json"
    if (-not (Test-Path -LiteralPath $packageJson)) {
        throw "还没有安装 SillyTavern。请先运行：jiuguan install"
    }
}

function Install-JgNodePackages {
    $paths = Get-JgPaths
    $registryArgs = @(Get-JgNpmRegistryArgs)

    Write-JgInfo "安装 SillyTavern 的 npm 依赖。"
    Push-Location -LiteralPath $paths.SillyTavern
    try {
        $args = @("install", "--no-audit", "--no-fund") + $registryArgs
        Invoke-JgExternal -FilePath "npm" -Arguments $args -Step "npm install"
    }
    finally {
        Pop-Location
    }
}

function Install-JgDeployment {
    $paths = Initialize-JgDirectories
    Ensure-JgDependencies

    if (-not (Test-JgUrl "https://github.com/")) {
        Write-JgWarn "当前访问 GitHub 可能不稳定。如果克隆失败，可以设置代理或指定镜像：`$env:JIUGUAN_SILLYTAVERN_REPO='你的镜像仓库地址'"
    }

    if (-not (Test-Path -LiteralPath $paths.SillyTavern)) {
        New-Item -ItemType Directory -Force -Path $paths.Root | Out-Null
        $cloned = $false

        foreach ($repo in @(Get-JgSillyTavernRepoCandidates)) {
            Write-JgInfo "拉取 SillyTavern：$repo"
            & git clone --depth 1 $repo $paths.SillyTavern
            if ($LASTEXITCODE -eq 0) {
                $cloned = $true
                break
            }

            Write-JgWarn "这个来源拉取失败，尝试下一个来源。"
            if (Test-Path -LiteralPath $paths.SillyTavern) {
                Remove-JgPathSafely -Path $paths.SillyTavern
            }
        }

        if (-not $cloned) {
            throw "SillyTavern 拉取失败。请检查网络，或设置 `$env:JIUGUAN_SILLYTAVERN_REPO 后重试：jiuguan install"
        }
    }
    elseif (-not (Test-Path -LiteralPath (Join-Path $paths.SillyTavern ".git"))) {
        throw "发现 $($paths.SillyTavern)，但它不是 Git 仓库。为避免覆盖你的文件，请先移动该目录后重试。"
    }
    else {
        Write-JgInfo "已发现 SillyTavern 目录，跳过克隆。"
    }

    Install-JgNodePackages
    Write-JgSuccess "安装完成。运行 jiuguan start 后访问 http://127.0.0.1:8000"
}

function Get-JgRunningProcess {
    $paths = Get-JgPaths
    if (-not (Test-Path -LiteralPath $paths.PidFile)) {
        return $null
    }

    $pidText = (Get-Content -LiteralPath $paths.PidFile -Raw).Trim()
    if (-not ($pidText -match "^\d+$")) {
        return $null
    }

    return Get-Process -Id ([int]$pidText) -ErrorAction SilentlyContinue
}

function Start-JgSillyTavern {
    Assert-JgSillyTavernInstalled
    $paths = Initialize-JgDirectories
    $running = Get-JgRunningProcess
    if ($running) {
        Write-JgSuccess "SillyTavern 已在运行，PID：$($running.Id)"
        return
    }

    $runner = Join-Path $paths.State "run-sillytavern.ps1"
    $safeStPath = $paths.SillyTavern.Replace("'", "''")
    $safeLogPath = $paths.MainLog.Replace("'", "''")
    $runnerContent = @"
Set-Location -LiteralPath '$safeStPath'
npm start *>> '$safeLogPath'
"@
    Set-Content -LiteralPath $runner -Value $runnerContent -Encoding UTF8

    Write-JgInfo "启动 SillyTavern。日志：$($paths.MainLog)"
    $process = Start-Process -FilePath "powershell.exe" -ArgumentList @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", $runner) -WindowStyle Hidden -PassThru
    Set-Content -LiteralPath $paths.PidFile -Value $process.Id -Encoding ASCII

    Start-Sleep -Seconds 2
    $running = Get-JgRunningProcess
    if (-not $running) {
        Write-JgWarn "启动进程很快退出了，请运行 jiuguan logs 查看原因。"
        if (Test-Path -LiteralPath $paths.PidFile) {
            Remove-Item -LiteralPath $paths.PidFile -Force
        }
        return
    }

    Write-JgSuccess "SillyTavern 已启动，PID：$($running.Id)"
    Write-Host "本机访问：http://127.0.0.1:8000"
}

function Stop-JgSillyTavern {
    $paths = Get-JgPaths
    $running = Get-JgRunningProcess
    if (-not $running) {
        if (Test-Path -LiteralPath $paths.PidFile) {
            Remove-Item -LiteralPath $paths.PidFile -Force
        }

        Write-JgInfo "SillyTavern 当前没有运行。"
        return
    }

    Write-JgInfo "停止 SillyTavern，PID：$($running.Id)"
    if (Test-JgCommand "taskkill") {
        & taskkill /PID $running.Id /T /F | Out-Null
    }
    else {
        Stop-Process -Id $running.Id -Force
    }

    if (Test-Path -LiteralPath $paths.PidFile) {
        Remove-Item -LiteralPath $paths.PidFile -Force
    }

    Write-JgSuccess "已停止。"
}

function Restart-JgSillyTavern {
    Stop-JgSillyTavern
    Start-JgSillyTavern
}

function Get-JgLanAddresses {
    $addresses = @()
    try {
        $addresses = Get-NetIPAddress -AddressFamily IPv4 -ErrorAction Stop |
            Where-Object { $_.IPAddress -notlike "127.*" -and $_.IPAddress -notlike "169.254.*" } |
            Select-Object -ExpandProperty IPAddress -Unique
    }
    catch {
        try {
            $addresses = [System.Net.Dns]::GetHostAddresses([System.Net.Dns]::GetHostName()) |
                Where-Object { $_.AddressFamily -eq [System.Net.Sockets.AddressFamily]::InterNetwork -and $_.IPAddressToString -notlike "127.*" } |
                ForEach-Object { $_.IPAddressToString } |
                Select-Object -Unique
        }
        catch {
            $addresses = @()
        }
    }

    return $addresses
}

function Show-JgStatus {
    $paths = Get-JgPaths
    $running = Get-JgRunningProcess

    Write-Host "214769SillyTavern：v$script:JiuguanVersion"
    Write-Host "安装目录：$($paths.Root)"

    if (Test-JgCommand "node") {
        try {
            Write-Host "Node.js：v$(Get-JgNodeVersionText)"
        }
        catch {
            Write-Host "Node.js：已安装但无法运行"
        }
    }
    else {
        Write-Host "Node.js：未安装"
    }

    if (Test-JgCommand "git") {
        Write-Host "Git：$(& git --version)"
    }
    else {
        Write-Host "Git：未安装"
    }

    if (Test-Path -LiteralPath (Join-Path $paths.SillyTavern ".git")) {
        $branch = (& git -C $paths.SillyTavern rev-parse --abbrev-ref HEAD 2>$null)
        $commit = (& git -C $paths.SillyTavern rev-parse --short HEAD 2>$null)
        Write-Host "SillyTavern：$branch $commit"
    }
    else {
        Write-Host "SillyTavern：未安装"
    }

    if ($running) {
        Write-Host "运行状态：运行中，PID $($running.Id)" -ForegroundColor Green
    }
    else {
        Write-Host "运行状态：未运行"
    }

    Write-Host "本机地址：http://127.0.0.1:8000"
    foreach ($ip in @(Get-JgLanAddresses)) {
        Write-Host "局域网地址：http://$ip`:8000"
    }

    Write-Host "手机访问电脑上的酒馆时，请确认电脑和手机在同一 Wi-Fi，并允许防火墙放行 Node.js。"
}

function Show-JgLogs {
    param([int]$Lines = 120)

    $paths = Get-JgPaths
    if (-not (Test-Path -LiteralPath $paths.MainLog)) {
        Write-JgWarn "还没有日志文件。请先运行 jiuguan start。"
        return
    }

    Get-Content -LiteralPath $paths.MainLog -Tail $Lines
}

function New-JgBackup {
    $paths = Initialize-JgDirectories
    Assert-JgSillyTavernInstalled

    $stamp = Get-Date -Format "yyyyMMdd-HHmmss"
    $stage = Join-Path $paths.State "backup-$stamp"
    $archive = Join-Path $paths.Backups "sillytavern-$stamp.zip"

    if (Test-Path -LiteralPath $stage) {
        Remove-JgPathSafely -Path $stage
    }

    New-Item -ItemType Directory -Force -Path $stage | Out-Null
    Set-Content -LiteralPath (Join-Path $stage "BACKUP_INFO.txt") -Value "jiuguan backup $stamp" -Encoding UTF8

    foreach ($item in @("data", "public/user", "config.yaml", "config.conf", "plugins")) {
        $source = Join-Path $paths.SillyTavern $item
        if (Test-Path -LiteralPath $source) {
            $target = Join-Path $stage $item
            $targetParent = Split-Path -Parent $target
            New-Item -ItemType Directory -Force -Path $targetParent | Out-Null
            Copy-Item -LiteralPath $source -Destination $target -Recurse -Force
        }
    }

    Compress-Archive -Path (Join-Path $stage "*") -DestinationPath $archive -Force
    Remove-JgPathSafely -Path $stage

    Write-JgSuccess "备份完成：$archive"
    return $archive
}

function Restore-JgBackup {
    param([string]$BackupPath)

    $paths = Initialize-JgDirectories
    Assert-JgSillyTavernInstalled

    if (-not $BackupPath) {
        $latest = Get-ChildItem -LiteralPath $paths.Backups -Filter "sillytavern-*.zip" -ErrorAction SilentlyContinue |
            Sort-Object LastWriteTime -Descending |
            Select-Object -First 1
        if (-not $latest) {
            throw "没有找到备份。请先运行：jiuguan backup"
        }

        $BackupPath = $latest.FullName
    }

    if (-not (Test-Path -LiteralPath $BackupPath)) {
        throw "找不到备份文件：$BackupPath"
    }

    $stamp = Get-Date -Format "yyyyMMdd-HHmmss"
    $stage = Join-Path $paths.State "restore-$stamp"
    if (Test-Path -LiteralPath $stage) {
        Remove-JgPathSafely -Path $stage
    }

    New-Item -ItemType Directory -Force -Path $stage | Out-Null
    Expand-Archive -LiteralPath $BackupPath -DestinationPath $stage -Force

    foreach ($item in @("data", "public/user", "config.yaml", "config.conf", "plugins")) {
        $source = Join-Path $stage $item
        if (Test-Path -LiteralPath $source) {
            $target = Join-Path $paths.SillyTavern $item
            $targetParent = Split-Path -Parent $target
            New-Item -ItemType Directory -Force -Path $targetParent | Out-Null

            if (Test-Path -LiteralPath $target) {
                Remove-JgPathSafely -Path $target
            }

            Copy-Item -LiteralPath $source -Destination $target -Recurse -Force
        }
    }

    Remove-JgPathSafely -Path $stage
    Write-JgSuccess "已恢复备份：$BackupPath"
}

function Update-JgTool {
    $paths = Initialize-JgDirectories
    $rawBase = $env:JIUGUAN_RAW_BASE_URL
    if (-not $rawBase -and (Test-Path -LiteralPath $paths.RawBaseFile)) {
        $rawBase = (Get-Content -LiteralPath $paths.RawBaseFile -Raw).Trim()
    }

    if (-not $rawBase) {
        Write-JgInfo "没有配置远程工具地址，跳过工具自身更新。"
        return
    }

    foreach ($relative in @("bin/jiuguan.ps1", "lib/jiuguan.ps1")) {
        $destination = Join-Path $paths.Tool $relative
        $temp = "$destination.tmp"
        Write-JgInfo "更新工具文件：$relative"
        $selectedRawBase = Invoke-JgDownloadToolFile -RelativePath $relative -Destination $temp -PreferredRawBase $rawBase
        if ($selectedRawBase) {
            $rawBase = $selectedRawBase
        }
        Move-Item -LiteralPath $temp -Destination $destination -Force
    }

    Set-Content -LiteralPath $paths.RawBaseFile -Value $rawBase -Encoding UTF8
    Write-JgSuccess "工具自身更新完成。"
}

function Update-JgDeployment {
    $paths = Initialize-JgDirectories
    Assert-JgSillyTavernInstalled
    Ensure-JgDependencies

    Update-JgTool
    $wasRunning = [bool](Get-JgRunningProcess)
    New-JgBackup

    if ($wasRunning) {
        Stop-JgSillyTavern
    }

    Write-JgInfo "更新 SillyTavern 代码。"
    Invoke-JgExternal -FilePath "git" -Arguments @("-C", $paths.SillyTavern, "fetch", "--all", "--prune") -Step "git fetch"
    Invoke-JgExternal -FilePath "git" -Arguments @("-C", $paths.SillyTavern, "pull", "--ff-only") -Step "git pull"
    Install-JgNodePackages

    if ($wasRunning) {
        Start-JgSillyTavern
    }

    Write-JgSuccess "更新完成。"
}

function Remove-JgPathSafely {
    param([Parameter(Mandatory = $true)][string]$Path)

    if (-not (Test-Path -LiteralPath $Path)) {
        return
    }

    $paths = Get-JgPaths
    $root = [System.IO.Path]::GetFullPath($paths.Root).TrimEnd([System.IO.Path]::DirectorySeparatorChar, [System.IO.Path]::AltDirectorySeparatorChar)
    $target = (Resolve-Path -LiteralPath $Path -ErrorAction Stop).Path.TrimEnd([System.IO.Path]::DirectorySeparatorChar, [System.IO.Path]::AltDirectorySeparatorChar)
    $home = [System.IO.Path]::GetFullPath($HOME).TrimEnd([System.IO.Path]::DirectorySeparatorChar, [System.IO.Path]::AltDirectorySeparatorChar)
    $driveRoot = [System.IO.Path]::GetPathRoot($target).TrimEnd([System.IO.Path]::DirectorySeparatorChar, [System.IO.Path]::AltDirectorySeparatorChar)

    if ($target.Equals($root, [System.StringComparison]::OrdinalIgnoreCase) -or
        $target.Equals($home, [System.StringComparison]::OrdinalIgnoreCase) -or
        $target.Equals($driveRoot, [System.StringComparison]::OrdinalIgnoreCase) -or
        -not $target.StartsWith($root + [System.IO.Path]::DirectorySeparatorChar, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "拒绝删除高风险路径：$target"
    }

    Remove-Item -LiteralPath $target -Recurse -Force
}
function Uninstall-JgDeployment {
    param([switch]$DeleteData)

    $paths = Get-JgPaths
    Stop-JgSillyTavern

    if (Test-Path -LiteralPath $paths.ShimCmd) {
        Remove-Item -LiteralPath $paths.ShimCmd -Force
    }

    if ($DeleteData) {
        foreach ($dir in @($paths.SillyTavern, $paths.Backups, $paths.Logs, $paths.State, $paths.Tool)) {
            if (Test-Path -LiteralPath $dir) {
                Remove-JgPathSafely -Path $dir
            }
        }

        Write-JgWarn "已删除工具和本地数据。"
    }
    else {
        if (Test-Path -LiteralPath $paths.Tool) {
            Remove-JgPathSafely -Path $paths.Tool
        }

        Write-JgSuccess "已卸载管理工具。SillyTavern 和备份仍保留在：$($paths.Root)"
    }

    Write-JgWarn "如果当前窗口仍能找到 jiuguan，请重新打开终端；PATH 会在新窗口里刷新。"
}

function Show-JgDataMenu {
    while ($true) {
        Write-Host ""
        Write-Host "用户数据"
        Write-Host "----------------------------"
        Write-Host "1. 备份用户数据"
        Write-Host "2. 恢复最新备份"
        Write-Host "0. 返回主菜单"
        $choice = Read-Host "请输入数字"

        try {
            switch ($choice) {
                "1" { New-JgBackup }
                "2" { Restore-JgBackup }
                "0" { return }
                default { Write-JgWarn "请输入 0 到 2 之间的数字。" }
            }
        }
        catch {
            Write-JgError $_.Exception.Message
        }

        if ($choice -ne "0") {
            Write-Host ""
            Read-Host "按回车返回" | Out-Null
        }
    }
}

function Invoke-JgUninstallMenu {
    while ($true) {
        Write-Host ""
        Write-Host "卸载"
        Write-Host "----------------------------"
        Write-Host "1. 卸载管理工具，保留 SillyTavern 和备份"
        Write-Host "2. 卸载并删除全部本地数据"
        Write-Host "0. 返回主菜单"
        $choice = Read-Host "请输入数字"

        try {
            switch ($choice) {
                "1" {
                    Uninstall-JgDeployment
                    return $true
                }
                "2" {
                    Write-JgWarn "这会删除 SillyTavern、本地数据、日志和备份。"
                    $confirm = Read-Host "确认删除请输入 DELETE"
                    if ($confirm -eq "DELETE") {
                        Uninstall-JgDeployment -DeleteData
                        return $true
                    }

                    Write-JgWarn "未输入 DELETE，已取消删除。"
                    return $false
                }
                "0" { return $false }
                default { Write-JgWarn "请输入 0 到 2 之间的数字。" }
            }
        }
        catch {
            Write-JgError $_.Exception.Message
            return $false
        }
    }
}

function Show-JgMenu {
    while ($true) {
        Write-Host ""
        Write-Host "214769SillyTavern 控制台 v$script:JiuguanVersion"
        Write-Host "----------------------------"
        Write-Host "1. 安装或修复 SillyTavern"
        Write-Host "2. 启动 SillyTavern"
        Write-Host "3. 停止 SillyTavern"
        Write-Host "4. 重启 SillyTavern"
        Write-Host "5. 查看状态和访问地址"
        Write-Host "6. 查看最近日志"
        Write-Host "7. 更新工具和 SillyTavern"
        Write-Host "8. 备份/恢复用户数据"
        Write-Host "9. 卸载"
        Write-Host "0. 退出"
        $choice = Read-Host "请输入数字"

        try {
            switch ($choice) {
                "1" { Install-JgDeployment }
                "2" { Start-JgSillyTavern }
                "3" { Stop-JgSillyTavern }
                "4" { Restart-JgSillyTavern }
                "5" { Show-JgStatus }
                "6" { Show-JgLogs -Lines 120 }
                "7" { Update-JgDeployment }
                "8" { Show-JgDataMenu }
                "9" {
                    if (Invoke-JgUninstallMenu) {
                        return
                    }
                }
                "0" { return }
                default { Write-JgWarn "请输入 0 到 9 之间的数字。" }
            }
        }
        catch {
            Write-JgError $_.Exception.Message
        }

        if ($choice -ne "0") {
            Write-Host ""
            Read-Host "按回车返回菜单" | Out-Null
        }
    }
}
function Show-JgHelp {
    Write-Host @"
214769SillyTavern v$script:JiuguanVersion

安装完成后会自动进入数字控制台；以后直接运行 jiuguan 也可以再次打开。

用法：
  jiuguan install              安装或修复依赖和 SillyTavern
  jiuguan update               更新工具和 SillyTavern，更新前自动备份
  jiuguan start                启动 SillyTavern
  jiuguan stop                 停止 SillyTavern
  jiuguan restart              重启 SillyTavern
  jiuguan status               查看版本、运行状态和访问地址
  jiuguan logs [行数]          查看最近日志，默认 120 行
  jiuguan backup               备份用户数据
  jiuguan restore [备份路径]   恢复备份；不传路径时恢复最新备份
  jiuguan uninstall            卸载管理工具，保留 SillyTavern 和备份
  jiuguan uninstall --delete-data  卸载并删除本地数据

常用环境变量：
  JIUGUAN_HOME                 自定义安装目录，默认：$HOME\214769SillyTavern
  JIUGUAN_NPM_REGISTRY         自定义 npm registry
  JIUGUAN_SILLYTAVERN_REPO     自定义 SillyTavern Git 仓库或镜像
"@
}
