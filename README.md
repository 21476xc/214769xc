# 214769SillyTavern

214769SillyTavern 是给中文小白用户准备的 SillyTavern 一键部署和维护工具。复制一条命令后，它会自动安装依赖、拉取 SillyTavern、安装 npm 依赖、启动服务，并进入数字控制台。

项目地址：`https://github.com/21476xc/214769xc`

## 一键安装

### Windows 10/11 PowerShell

打开 PowerShell，复制运行：

```powershell
$p="$env:TEMP\214769-install.ps1"; iwr https://cdn.jsdelivr.net/gh/21476xc/214769xc@2a769b4/scripts/install.ps1 -UseBasicParsing -OutFile $p -ErrorAction Stop; powershell -NoProfile -ExecutionPolicy Bypass -File $p
```

### macOS / Linux

打开终端，复制运行：

```bash
curl -fsSL https://cdn.jsdelivr.net/gh/21476xc/214769xc@main/install.sh | bash
```

### Android Termux

请使用 F-Droid 版 Termux，不建议使用 Play 商店旧版。打开 Termux，复制运行：

```bash
pkg i -y wget && wget -qO- https://cdn.jsdelivr.net/gh/21476xc/214769xc@main/install.sh | bash
```

Termux 短命令会先用 `wget` 下载安装脚本，脚本内部再自动完整升级 Termux 基础包，避免只更新 `curl` 导致底层库不匹配。

### 下载优化

安装器会优先使用较快的 CDN 下载管理工具，并自动选择 `npmmirror` 安装 npm 依赖。拉取 SillyTavern 时，会先对比官方仓库与加速源的 `release` 提交哈希；只有完全一致才使用加速源，下载完成后会把长期更新地址切回官方仓库。

如果网络中途断开，安装器会自动重试并清理不完整的临时目录。再次运行同一条一键命令即可继续，不需要手动删除 `SillyTavern` 文件夹。

## 安装完成后

安装成功后会自动启动 SillyTavern，并显示访问地址。

- 本机访问：`http://127.0.0.1:8000`
- 手机访问电脑上的酒馆：运行 `jiuguan status`，看输出里的局域网地址。
- Termux：以后每次打开 Termux 会自动进入数字控制台。

默认安装位置：

| 平台 | 默认目录 |
| --- | --- |
| Windows | `%USERPROFILE%\214769SillyTavern` |
| macOS/Linux/Termux | `$HOME/214769SillyTavern` |

## 数字控制台

安装后会自动进入控制台。以后也可以手动输入：

```bash
jiuguan
```

菜单功能：

| 数字 | 功能 |
| --- | --- |
| 1 | 安装或修复 SillyTavern |
| 2 | 启动 SillyTavern |
| 3 | 停止 SillyTavern |
| 4 | 重启 SillyTavern |
| 5 | 查看状态和访问地址 |
| 6 | 查看最近日志 |
| 7 | 更新工具和 SillyTavern |
| 8 | 备份/恢复用户数据 |
| 9 | 卸载 |
| 0 | 退出 |

## 常用命令

不想用菜单时，也可以直接输入命令：

| 命令 | 用途 |
| --- | --- |
| `jiuguan` | 打开数字控制台 |
| `jiuguan install` | 安装或修复依赖和 SillyTavern |
| `jiuguan start` | 启动 SillyTavern |
| `jiuguan stop` | 停止 SillyTavern |
| `jiuguan restart` | 重启 SillyTavern |
| `jiuguan status` | 查看版本、运行状态和访问地址 |
| `jiuguan logs` | 查看最近日志 |
| `jiuguan backup` | 备份角色、聊天、配置和插件等用户数据 |
| `jiuguan restore` | 恢复最新备份 |
| `jiuguan update` | 更新工具和 SillyTavern，更新前自动备份 |
| `jiuguan uninstall` | 卸载管理工具，保留数据 |
| `jiuguan uninstall --delete-data` | 卸载并删除本地数据 |

## 卸载和重复测试

普通卸载，保留 SillyTavern 和备份：

```bash
jiuguan uninstall
```

彻底删除本地数据：

```bash
jiuguan uninstall --delete-data
```

Termux/macOS/Linux 想清空后重新测试：

```bash
jiuguan uninstall --delete-data 2>/dev/null || true
rm -rf "$HOME/214769SillyTavern" "$HOME/.local/bin/jiuguan" install.sh
[ -n "${PREFIX:-}" ] && rm -f "$PREFIX/bin/jiuguan"
sed -i '/# 214769SillyTavern auto menu begin/,/# 214769SillyTavern auto menu end/d' "$HOME/.bashrc" 2>/dev/null || true
hash -r 2>/dev/null || true
```

Windows PowerShell 想清空后重新测试：

```powershell
jiuguan uninstall --delete-data
Remove-Item -Recurse -Force "$env:USERPROFILE\214769SillyTavern" -ErrorAction SilentlyContinue
```

## 数据安全

`jiuguan update` 会先自动备份，再更新 SillyTavern。备份包含：

- `data`
- `public/user`
- `config.yaml`
- `config.conf`
- `plugins`

备份位置：

| 平台 | 备份文件 |
| --- | --- |
| Windows | `%USERPROFILE%\214769SillyTavern\backups\sillytavern-时间.zip` |
| macOS/Linux/Termux | `$HOME/214769SillyTavern/backups/sillytavern-时间.tar.gz` |

## 救急命令

### Termux 短命令失败

如果 Termux 短命令连脚本都下载不下来，可以先换源：

```bash
termux-change-repo
```

如果遇到 `curl/wget` 损坏、底层库不匹配，使用这条完整兼容命令：

```bash
tmp="${TMPDIR:-/tmp}/jiuguan-install.sh"; apt-get update && DEBIAN_FRONTEND=noninteractive apt-get full-upgrade -y -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold" && DEBIAN_FRONTEND=noninteractive apt-get install -y -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold" curl wget ca-certificates && (curl -fsSL https://cdn.jsdelivr.net/gh/21476xc/214769xc@main/install.sh -o "$tmp" || wget -qO "$tmp" https://cdn.jsdelivr.net/gh/21476xc/214769xc@main/install.sh) && bash "$tmp"
```

### macOS/Linux 没有 curl

如果系统没有 `curl`，用 `wget`：

```bash
wget -qO- https://cdn.jsdelivr.net/gh/21476xc/214769xc@main/install.sh | bash
```

## 常见问题

### Windows 没有 Git 或 Node.js

工具会优先复用已有安装；缺失时尝试使用 `winget` 安装。若 `winget` 不可用，请手动安装：

- Git: https://git-scm.com/download/win
- Node.js LTS: https://nodejs.org/

### macOS 提示安装 Homebrew

macOS 缺少 Git 或 Node.js 时，工具会引导安装 Homebrew。这个过程可能要求输入电脑密码。

### Linux 不是 Debian/Ubuntu

v1 只会在 Debian/Ubuntu 系自动使用 `apt` 安装依赖。其他发行版请先手动安装 Git、Node.js 18+、npm、curl、tar、gzip，再运行 `jiuguan install`。

### Android 后台运行不稳定

Android 可能会清理 Termux 后台进程。长时间使用时请保持 Termux 活跃，或在 Termux 里配置 wakelock。v1 不注册系统服务。

### 从手机存储导入角色或备份

Termux 安装后可以运行：

```bash
termux-setup-storage
```

### iPhone/iPad 能部署吗

不能在 iOS 本机部署。iPhone/iPad 可以通过浏览器访问电脑或 Android Termux 上运行的 SillyTavern。

## 高级设置

自定义安装目录：

```bash
JIUGUAN_HOME="$HOME/SillyTavernBox" bash <(curl -fsSL https://cdn.jsdelivr.net/gh/21476xc/214769xc@main/install.sh)
```

Windows PowerShell：

```powershell
$env:JIUGUAN_HOME = "D:\SillyTavernBox"
$p="$env:TEMP\214769-install.ps1"; iwr https://cdn.jsdelivr.net/gh/21476xc/214769xc@2a769b4/scripts/install.ps1 -UseBasicParsing -OutFile $p -ErrorAction Stop; powershell -NoProfile -ExecutionPolicy Bypass -File $p
```

一般不需要手动设置镜像。确实需要指定自定义 SillyTavern 仓库时：

```bash
JIUGUAN_SILLYTAVERN_REPO="https://github.com/SillyTavern/SillyTavern.git" jiuguan install
```

Windows PowerShell：

```powershell
$env:JIUGUAN_SILLYTAVERN_REPO = "你的镜像仓库地址"
jiuguan install
```

指定 npm 镜像源：

```bash
JIUGUAN_NPM_REGISTRY="https://registry.npmmirror.com" jiuguan install
```

Windows PowerShell 对应写法：

```powershell
$env:JIUGUAN_NPM_REGISTRY = "https://registry.npmmirror.com"
jiuguan install
```

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

本地验证：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tests\validate.ps1
```

发布前建议在 Windows、macOS/Linux 和 Termux 上分别验证一次 `install`、`start`、`status`、`backup`、`update`、`stop`、`uninstall`。
