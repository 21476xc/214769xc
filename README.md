# 214769SillyTavern

214769SillyTavern 是一个面向中文小白用户的 SillyTavern 一键部署和维护工具。用户复制一条命令即可安装，之后用 `jiuguan` 管理启动、更新、日志、备份、恢复和卸载。

> 当前发布 Raw 地址：`https://raw.githubusercontent.com/21476xc/214769xc/main`。

## 一键安装

### Windows 10/11 PowerShell

```powershell
irm https://raw.githubusercontent.com/21476xc/214769xc/main/install.ps1 | iex
```

本地开发时可以先只安装管理命令，不拉取 SillyTavern：

```powershell
.\install.ps1 -SkipInstall
```

### macOS / Linux

```bash
curl -fsSL https://raw.githubusercontent.com/21476xc/214769xc/main/install.sh | bash
```

本地开发时可以先只安装管理命令：

```bash
bash ./install.sh --skip-install
```

### Android Termux

请使用 F-Droid 版 Termux，不建议使用 Play 商店旧版。

```bash
pkg update -y && pkg install -y curl
curl -fsSL https://raw.githubusercontent.com/21476xc/214769xc/main/install.sh | bash
```

如果要从手机存储导入角色或备份，可以在安装后运行：

```bash
termux-setup-storage
```

## 常用命令

```bash
jiuguan install
jiuguan start
jiuguan status
jiuguan logs
jiuguan backup
jiuguan update
jiuguan stop
jiuguan restore
jiuguan uninstall
```

| 命令 | 用途 |
| --- | --- |
| `jiuguan install` | 安装或修复 Git、Node.js、SillyTavern 和 npm 依赖 |
| `jiuguan start` | 启动 SillyTavern |
| `jiuguan stop` | 停止 SillyTavern |
| `jiuguan restart` | 重启 SillyTavern |
| `jiuguan status` | 查看安装目录、版本、运行状态和访问地址 |
| `jiuguan logs [行数]` | 查看最近日志，默认 120 行 |
| `jiuguan backup` | 备份角色、聊天、配置和插件等用户数据 |
| `jiuguan restore [备份路径]` | 恢复指定备份；不传路径时恢复最新备份 |
| `jiuguan update` | 更新工具和 SillyTavern，更新前自动备份 |
| `jiuguan uninstall` | 卸载管理工具，默认保留 SillyTavern 和备份 |
| `jiuguan uninstall --delete-data` | 卸载并删除本地 SillyTavern、日志和备份 |

## 访问地址

桌面端启动后默认访问：

```text
http://127.0.0.1:8000
```

如果要用手机访问电脑上的酒馆，运行：

```bash
jiuguan status
```

然后在手机浏览器打开输出里的局域网地址，例如：

```text
http://192.168.1.23:8000
```

请确认手机和电脑在同一个 Wi-Fi 下，并允许系统防火墙放行 Node.js。

## 安装位置

默认安装到当前用户目录，不写系统目录：

| 平台 | 默认目录 |
| --- | --- |
| Windows | `%USERPROFILE%\214769SillyTavern` |
| macOS/Linux/Termux | `$HOME/214769SillyTavern` |

可以通过环境变量改安装目录。

Windows PowerShell：

```powershell
$env:JIUGUAN_HOME = "D:\SillyTavernBox"
irm https://raw.githubusercontent.com/21476xc/214769xc/main/install.ps1 | iex
```

macOS/Linux/Termux：

```bash
JIUGUAN_HOME="$HOME/SillyTavernBox" bash <(curl -fsSL https://raw.githubusercontent.com/21476xc/214769xc/main/install.sh)
```

## 网络和镜像

工具会优先使用官方 GitHub 和 npm 源。如果 npm 官方源不可用，会自动改用 `https://registry.npmmirror.com`。

如果 GitHub 拉取失败，可以手动指定 SillyTavern 镜像仓库。

Windows PowerShell：

```powershell
$env:JIUGUAN_SILLYTAVERN_REPO = "https://github.com/SillyTavern/SillyTavern.git"
jiuguan install
```

macOS/Linux/Termux：

```bash
JIUGUAN_SILLYTAVERN_REPO="https://github.com/SillyTavern/SillyTavern.git" jiuguan install
```

如果你有自己的 npm 代理源，也可以指定：

```bash
JIUGUAN_NPM_REGISTRY="https://registry.npmmirror.com" jiuguan install
```

Windows PowerShell 对应写法：

```powershell
$env:JIUGUAN_NPM_REGISTRY = "https://registry.npmmirror.com"
jiuguan install
```

## 更新和数据安全

`jiuguan update` 会先执行备份，再更新 SillyTavern 代码和 npm 依赖。备份包含常见用户数据：

- `data`
- `public/user`
- `config.yaml`
- `config.conf`
- `plugins`

备份目录：

| 平台 | 备份格式 |
| --- | --- |
| Windows | `%USERPROFILE%\214769SillyTavern\backups\sillytavern-时间.zip` |
| macOS/Linux/Termux | `$HOME/214769SillyTavern/backups/sillytavern-时间.tar.gz` |

## 常见问题

### PowerShell 提示无法运行脚本

请用 README 里的 `irm ... | iex` 命令，安装后的 `jiuguan.cmd` 会自动使用 `-ExecutionPolicy Bypass` 调用管理脚本。

### Windows 没有 Git 或 Node.js

工具会优先复用已有安装；缺失时尝试使用 `winget` 安装。若 `winget` 不可用，请手动安装：

- Git: https://git-scm.com/download/win
- Node.js LTS: https://nodejs.org/

安装后重新打开 PowerShell，再运行：

```powershell
jiuguan install
```

### Linux 不是 Debian/Ubuntu

v1 只会在 Debian/Ubuntu 系自动使用 `apt` 安装依赖。其他发行版请先手动安装 Git、Node.js 18+、npm、curl、tar、gzip，再运行：

```bash
jiuguan install
```

### Android 后台运行不稳定

Android 可能会清理 Termux 后台进程。长时间使用时请保持 Termux 活跃，或在 Termux 里配置 wakelock。v1 不注册系统服务。

### iPhone/iPad 能部署吗

不能在 iOS 本机部署。iPhone/iPad 可以通过浏览器访问电脑或 Android Termux 上运行的 SillyTavern。

## 开发者说明

项目结构：

```text
.
├── install.ps1
├── install.sh
├── scripts/
│   ├── install.ps1
│   └── install.sh
├── bin/
│   ├── jiuguan.ps1
│   └── jiuguan.sh
├── lib/
│   ├── jiuguan.ps1
│   ├── jiuguan.sh
│   └── README.md
└── tests/
    └── validate.ps1
```

本地语法和入口验证：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tests\validate.ps1
```

发布前需要做两件事：

1. 确认 GitHub 仓库地址为 `https://github.com/21476xc/214769xc`。
2. 在 Windows、macOS/Linux 和 Termux 上分别验证一次 `install`、`start`、`status`、`backup`、`update`、`stop`、`uninstall`。