#!/usr/bin/env bash

JIUGUAN_VERSION="0.1.0"
JG_ST_REPO_DEFAULT="https://github.com/SillyTavern/SillyTavern.git"
JG_NPM_OFFICIAL_REGISTRY="https://registry.npmjs.org/"
JG_NPM_MIRROR_REGISTRY="https://registry.npmmirror.com"
JG_NPM_REGISTRY_ARGS=()

jg_info() { printf '[信息] %s\n' "$*"; }
jg_success() { printf '[完成] %s\n' "$*"; }
jg_warn() { printf '[提醒] %s\n' "$*"; }
jg_die() { printf '[错误] %s\n' "$*" >&2; exit 1; }

jg_load_paths() {
    JG_ROOT="${JIUGUAN_HOME:-$HOME/jiuguan}"
    JG_TOOL="$JG_ROOT/.jiuguan-tool"
    JG_BIN="$JG_TOOL/bin"
    JG_LIB="$JG_TOOL/lib"
    JG_ST="$JG_ROOT/SillyTavern"
    JG_STATE="$JG_ROOT/.state"
    JG_LOG_DIR="$JG_ROOT/logs"
    JG_BACKUPS="$JG_ROOT/backups"
    JG_PID="$JG_STATE/sillytavern.pid"
    JG_LOG="$JG_LOG_DIR/sillytavern.log"
    JG_RAW_BASE_FILE="$JG_TOOL/raw-base-url.txt"
}

jg_init_dirs() {
    jg_load_paths
    mkdir -p "$JG_ROOT" "$JG_TOOL" "$JG_BIN" "$JG_LIB" "$JG_STATE" "$JG_LOG_DIR" "$JG_BACKUPS"
}

jg_command_exists() {
    command -v "$1" >/dev/null 2>&1
}

jg_is_termux() {
    [[ -n "${TERMUX_VERSION:-}" ]] || [[ "${PREFIX:-}" == *"/com.termux/"* ]] || [[ -d "/data/data/com.termux/files/usr" ]]
}

jg_is_macos() {
    [[ "$(uname -s)" == "Darwin" ]]
}

jg_is_linux() {
    [[ "$(uname -s)" == "Linux" ]]
}

jg_run() {
    local step="$1"
    shift
    "$@" || jg_die "$step 失败。请检查上面的错误信息，然后重试：jiuguan $step"
}

jg_use_sudo() {
    if [[ "${EUID:-$(id -u)}" -eq 0 ]]; then
        "$@"
    elif jg_command_exists sudo; then
        sudo "$@"
    else
        jg_die "需要管理员权限，但系统没有 sudo。请手动安装 Git、Node.js、npm 后重试。"
    fi
}

jg_install_homebrew_if_needed() {
    if jg_command_exists brew; then
        return
    fi

    jg_warn "没有检测到 Homebrew，准备使用官方脚本安装。安装过程可能会要求输入电脑密码。"
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)" || jg_die "Homebrew 安装失败。请访问 https://brew.sh/ 手动安装后重试。"

    if [[ -x /opt/homebrew/bin/brew ]]; then
        eval "$(/opt/homebrew/bin/brew shellenv)"
    elif [[ -x /usr/local/bin/brew ]]; then
        eval "$(/usr/local/bin/brew shellenv)"
    fi
}

jg_install_debian_deps() {
    if ! jg_command_exists apt-get; then
        return 1
    fi

    jg_info "使用 apt 安装基础依赖。"
    jg_use_sudo apt-get update
    jg_use_sudo env DEBIAN_FRONTEND=noninteractive apt-get install -y git curl ca-certificates tar gzip nodejs npm
    return 0
}

jg_node_major() {
    if ! jg_command_exists node; then
        echo 0
        return
    fi

    node --version 2>/dev/null | sed 's/^v//' | awk -F. '{print $1}'
}

jg_ensure_node18() {
    local major
    major="$(jg_node_major)"
    if [[ "$major" =~ ^[0-9]+$ ]] && [[ "$major" -ge 18 ]]; then
        return
    fi

    if jg_is_termux; then
        jg_warn "当前 Node.js 版本较旧，尝试通过 Termux pkg 更新。"
        pkg install -y nodejs || jg_die "Node.js 更新失败。请运行 pkg update && pkg install nodejs 后重试。"
        return
    fi

    if jg_is_macos; then
        jg_install_homebrew_if_needed
        brew install node || brew upgrade node || jg_die "Node.js 安装失败。请访问 https://nodejs.org/ 手动安装 LTS 版本。"
        return
    fi

    if jg_is_linux && jg_command_exists apt-get; then
        jg_warn "系统自带 Node.js 版本较旧，准备使用 NodeSource 安装 LTS 版本。"
        curl -fsSL https://deb.nodesource.com/setup_lts.x | jg_use_sudo bash - || jg_die "NodeSource 配置失败。请手动安装 Node.js 18 或更新版本。"
        jg_use_sudo env DEBIAN_FRONTEND=noninteractive apt-get install -y nodejs
        return
    fi

    jg_die "Node.js 版本过旧。请手动安装 Node.js 18 或更新版本后重试。"
}

jg_ensure_dependencies() {
    jg_info "检查 Git、Node.js 和 npm。"

    if jg_is_termux; then
        jg_info "检测到 Termux。请确认使用的是 F-Droid 版 Termux。"
        pkg update -y
        pkg install -y git nodejs curl tar gzip || jg_die "Termux 依赖安装失败。请运行 pkg update 后重试。"
        if jg_command_exists termux-setup-storage; then
            jg_info "如需从手机存储导入角色或备份，可稍后运行 termux-setup-storage。"
        fi
    elif jg_is_macos; then
        jg_install_homebrew_if_needed
        brew install git node || true
    elif jg_is_linux; then
        if ! jg_install_debian_deps; then
            if ! jg_command_exists git || ! jg_command_exists node || ! jg_command_exists npm; then
                jg_die "当前 Linux 发行版不是 Debian/Ubuntu 系。请手动安装 Git、Node.js 18+ 和 npm 后重试。"
            fi
        fi
    else
        jg_die "暂不支持当前系统：$(uname -s)。"
    fi

    jg_ensure_node18

    if ! jg_command_exists git; then
        jg_die "没有找到 Git。请安装 Git 后重试。"
    fi

    if ! jg_command_exists npm; then
        jg_die "没有找到 npm。请安装 Node.js LTS 后重试。"
    fi

    jg_success "依赖检查完成。"
}

jg_url_ok() {
    local url="$1"
    curl -fsI --max-time 8 "$url" >/dev/null 2>&1
}

jg_set_npm_registry_args() {
    JG_NPM_REGISTRY_ARGS=()

    if [[ -n "${JIUGUAN_NPM_REGISTRY:-}" ]]; then
        jg_info "使用自定义 npm registry：$JIUGUAN_NPM_REGISTRY"
        JG_NPM_REGISTRY_ARGS=(--registry "$JIUGUAN_NPM_REGISTRY")
        return
    fi

    if npm ping --registry "$JG_NPM_OFFICIAL_REGISTRY" >/dev/null 2>&1; then
        return
    fi

    jg_warn "npm 官方源暂时不可用，改用 npmmirror。"
    JG_NPM_REGISTRY_ARGS=(--registry "$JG_NPM_MIRROR_REGISTRY")
}

jg_repo_candidates() {
    if [[ -n "${JIUGUAN_SILLYTAVERN_REPO:-}" ]]; then
        printf '%s\n' "$JIUGUAN_SILLYTAVERN_REPO"
    fi
    printf '%s\n' "$JG_ST_REPO_DEFAULT"
}

jg_assert_sillytavern_installed() {
    jg_load_paths
    [[ -f "$JG_ST/package.json" ]] || jg_die "还没有安装 SillyTavern。请先运行：jiuguan install"
}

jg_install_node_packages() {
    jg_load_paths
    jg_set_npm_registry_args
    jg_info "安装 SillyTavern 的 npm 依赖。"
    (cd "$JG_ST" && npm install --no-audit --no-fund "${JG_NPM_REGISTRY_ARGS[@]}") || jg_die "npm install 失败。请检查网络，或设置 JIUGUAN_NPM_REGISTRY 后重试。"
}

jg_install() {
    jg_init_dirs
    jg_ensure_dependencies

    if ! jg_url_ok "https://github.com/"; then
        jg_warn "当前访问 GitHub 可能不稳定。如果克隆失败，可以设置 JIUGUAN_SILLYTAVERN_REPO 为镜像仓库后重试。"
    fi

    if [[ ! -e "$JG_ST" ]]; then
        local cloned=0 repo
        while IFS= read -r repo; do
            [[ -n "$repo" ]] || continue
            jg_info "拉取 SillyTavern：$repo"
            if git clone --depth 1 "$repo" "$JG_ST"; then
                cloned=1
                break
            fi
            jg_warn "这个来源拉取失败，尝试下一个来源。"
            rm -rf -- "$JG_ST"
        done < <(jg_repo_candidates)

        [[ "$cloned" -eq 1 ]] || jg_die "SillyTavern 拉取失败。请检查网络，或设置 JIUGUAN_SILLYTAVERN_REPO 后重试：jiuguan install"
    elif [[ ! -d "$JG_ST/.git" ]]; then
        jg_die "发现 $JG_ST，但它不是 Git 仓库。为避免覆盖你的文件，请先移动该目录后重试。"
    else
        jg_info "已发现 SillyTavern 目录，跳过克隆。"
    fi

    jg_install_node_packages
    jg_success "安装完成。运行 jiuguan start 后访问 http://127.0.0.1:8000"
}

jg_is_running() {
    jg_load_paths
    [[ -f "$JG_PID" ]] || return 1
    local pid
    pid="$(tr -d '[:space:]' < "$JG_PID")"
    [[ "$pid" =~ ^[0-9]+$ ]] || return 1
    kill -0 "$pid" >/dev/null 2>&1
}

jg_start() {
    jg_assert_sillytavern_installed
    jg_init_dirs

    if jg_is_running; then
        jg_success "SillyTavern 已在运行，PID：$(cat "$JG_PID")"
        return
    fi

    jg_info "启动 SillyTavern。日志：$JG_LOG"
    (
        cd "$JG_ST"
        nohup npm start >> "$JG_LOG" 2>&1 &
        echo $! > "$JG_PID"
    )

    sleep 2
    if jg_is_running; then
        jg_success "SillyTavern 已启动，PID：$(cat "$JG_PID")"
        printf '本机访问：http://127.0.0.1:8000\n'
        if jg_is_termux; then
            jg_warn "Android 可能会清理后台进程，长时间运行时请保持 Termux 活跃或配置 wakelock。"
        fi
    else
        jg_warn "启动进程很快退出了，请运行 jiuguan logs 查看原因。"
    fi
}

jg_stop() {
    jg_load_paths
    if ! [[ -f "$JG_PID" ]]; then
        jg_info "SillyTavern 当前没有运行。"
        return
    fi

    local pid
    pid="$(tr -d '[:space:]' < "$JG_PID")"
    if ! [[ "$pid" =~ ^[0-9]+$ ]] || ! kill -0 "$pid" >/dev/null 2>&1; then
        rm -f -- "$JG_PID"
        jg_info "SillyTavern 当前没有运行。"
        return
    fi

    jg_info "停止 SillyTavern，PID：$pid"
    if jg_command_exists pkill; then
        pkill -TERM -P "$pid" >/dev/null 2>&1 || true
    fi
    kill "$pid" >/dev/null 2>&1 || true
    sleep 2
    if kill -0 "$pid" >/dev/null 2>&1; then
        kill -9 "$pid" >/dev/null 2>&1 || true
    fi
    rm -f -- "$JG_PID"
    jg_success "已停止。"
}

jg_restart() {
    jg_stop
    jg_start
}

jg_lan_addresses() {
    {
        if jg_command_exists ip; then
            ip -4 route get 1.1.1.1 2>/dev/null | awk '{for (i=1;i<=NF;i++) if ($i=="src") print $(i+1)}'
            ip -4 addr show 2>/dev/null | awk '/inet / {print $2}' | cut -d/ -f1
        fi
        if jg_command_exists hostname; then
            hostname -I 2>/dev/null | tr ' ' '\n'
        fi
        if jg_command_exists ifconfig; then
            ifconfig 2>/dev/null | awk '/inet / && $2 != "127.0.0.1" {print $2}' | sed 's/addr://'
        fi
    } | awk 'NF && $1 !~ /^127\./ && $1 !~ /^169\.254\./ {print $1}' | sort -u
}

jg_status() {
    jg_load_paths
    printf '酒馆部署工具：v%s\n' "$JIUGUAN_VERSION"
    printf '安装目录：%s\n' "$JG_ROOT"

    if jg_command_exists node; then
        printf 'Node.js：%s\n' "$(node --version)"
    else
        printf 'Node.js：未安装\n'
    fi

    if jg_command_exists git; then
        printf 'Git：%s\n' "$(git --version)"
    else
        printf 'Git：未安装\n'
    fi

    if [[ -d "$JG_ST/.git" ]]; then
        local branch commit
        branch="$(git -C "$JG_ST" rev-parse --abbrev-ref HEAD 2>/dev/null || true)"
        commit="$(git -C "$JG_ST" rev-parse --short HEAD 2>/dev/null || true)"
        printf 'SillyTavern：%s %s\n' "$branch" "$commit"
    else
        printf 'SillyTavern：未安装\n'
    fi

    if jg_is_running; then
        printf '运行状态：运行中，PID %s\n' "$(cat "$JG_PID")"
    else
        printf '运行状态：未运行\n'
    fi

    printf '本机地址：http://127.0.0.1:8000\n'
    while IFS= read -r ip; do
        [[ -n "$ip" ]] && printf '局域网地址：http://%s:8000\n' "$ip"
    done < <(jg_lan_addresses)
    printf '手机访问电脑上的酒馆时，请确认电脑和手机在同一 Wi-Fi，并允许防火墙放行 Node.js。\n'
}

jg_logs() {
    local lines="${1:-120}"
    [[ "$lines" =~ ^[0-9]+$ ]] || lines=120
    jg_load_paths
    [[ -f "$JG_LOG" ]] || jg_die "还没有日志文件。请先运行 jiuguan start。"
    tail -n "$lines" "$JG_LOG"
}

jg_backup() {
    jg_init_dirs
    jg_assert_sillytavern_installed

    local stamp stage archive item
    stamp="$(date +%Y%m%d-%H%M%S)"
    stage="$JG_STATE/backup-$stamp"
    archive="$JG_BACKUPS/sillytavern-$stamp.tar.gz"

    rm -rf -- "$stage"
    mkdir -p "$stage"
    printf 'jiuguan backup %s\n' "$stamp" > "$stage/BACKUP_INFO.txt"

    for item in data public/user config.yaml config.conf plugins; do
        if [[ -e "$JG_ST/$item" ]]; then
            mkdir -p "$(dirname "$stage/$item")"
            cp -a "$JG_ST/$item" "$stage/$item"
        fi
    done

    tar -czf "$archive" -C "$stage" .
    rm -rf -- "$stage"
    jg_success "备份完成：$archive"
    printf '%s\n' "$archive"
}

jg_restore() {
    local backup_path="${1:-}"
    jg_init_dirs
    jg_assert_sillytavern_installed

    if [[ -z "$backup_path" ]]; then
        backup_path="$(ls -t "$JG_BACKUPS"/sillytavern-*.tar.gz 2>/dev/null | head -n 1 || true)"
        [[ -n "$backup_path" ]] || jg_die "没有找到备份。请先运行：jiuguan backup"
    fi

    [[ -f "$backup_path" ]] || jg_die "找不到备份文件：$backup_path"

    local stamp stage item source target
    stamp="$(date +%Y%m%d-%H%M%S)"
    stage="$JG_STATE/restore-$stamp"
    rm -rf -- "$stage"
    mkdir -p "$stage"
    tar -xzf "$backup_path" -C "$stage"

    for item in data public/user config.yaml config.conf plugins; do
        source="$stage/$item"
        target="$JG_ST/$item"
        if [[ -e "$source" ]]; then
            case "$target" in
                "$JG_ST"/*) rm -rf -- "$target" ;;
                *) jg_die "恢复目标路径异常：$target" ;;
            esac
            mkdir -p "$(dirname "$target")"
            cp -a "$source" "$target"
        fi
    done

    rm -rf -- "$stage"
    jg_success "已恢复备份：$backup_path"
}

jg_update_tool() {
    jg_init_dirs
    local raw_base="${JIUGUAN_RAW_BASE_URL:-}"
    if [[ -z "$raw_base" && -f "$JG_RAW_BASE_FILE" ]]; then
        raw_base="$(tr -d '\r\n' < "$JG_RAW_BASE_FILE")"
    fi

    if [[ -z "$raw_base" || "$raw_base" == *"your-name/jiuguan"* ]]; then
        jg_info "没有配置远程工具地址，跳过工具自身更新。"
        return
    fi

    local relative destination temp
    for relative in bin/jiuguan.sh lib/jiuguan.sh; do
        destination="$JG_TOOL/$relative"
        temp="$destination.tmp"
        jg_info "更新工具文件：$relative"
        curl -fsSL "$raw_base/$relative" -o "$temp" || jg_die "下载 $relative 失败。请检查网络后重试。"
        mv "$temp" "$destination"
    done
    chmod +x "$JG_BIN/jiuguan.sh"
    jg_success "工具自身更新完成。"
}

jg_update() {
    jg_init_dirs
    jg_assert_sillytavern_installed
    jg_ensure_dependencies
    jg_update_tool

    local was_running=0
    if jg_is_running; then
        was_running=1
    fi

    jg_backup >/dev/null

    if [[ "$was_running" -eq 1 ]]; then
        jg_stop
    fi

    jg_info "更新 SillyTavern 代码。"
    git -C "$JG_ST" fetch --all --prune || jg_die "git fetch 失败。请检查网络后重试。"
    git -C "$JG_ST" pull --ff-only || jg_die "git pull 失败。请确认没有手动修改 SillyTavern 代码。"
    jg_install_node_packages

    if [[ "$was_running" -eq 1 ]]; then
        jg_start
    fi

    jg_success "更新完成。"
}

jg_safe_rm_rf() {
    local path="$1"
    [[ -n "$path" ]] || jg_die "拒绝删除空路径。"
    case "$path" in
        /|"$HOME"|"$HOME/"|"$JG_ROOT")
            jg_die "拒绝删除高风险路径：$path"
            ;;
    esac
    rm -rf -- "$path"
}

jg_shim_path() {
    if jg_is_termux && [[ -n "${PREFIX:-}" ]]; then
        printf '%s\n' "$PREFIX/bin/jiuguan"
    else
        printf '%s\n' "$HOME/.local/bin/jiuguan"
    fi
}

jg_uninstall() {
    local delete_data="${1:-0}"
    jg_load_paths
    jg_stop

    local shim
    shim="$(jg_shim_path)"
    rm -f -- "$shim"

    if [[ "$delete_data" == "1" ]]; then
        for path in "$JG_ST" "$JG_BACKUPS" "$JG_LOG_DIR" "$JG_STATE" "$JG_TOOL"; do
            [[ -e "$path" ]] && jg_safe_rm_rf "$path"
        done
        jg_warn "已删除工具和本地数据。"
    else
        [[ -e "$JG_TOOL" ]] && jg_safe_rm_rf "$JG_TOOL"
        jg_success "已卸载管理工具。SillyTavern 和备份仍保留在：$JG_ROOT"
    fi

    jg_warn "如果当前窗口仍能找到 jiuguan，请重新打开终端；PATH 会在新窗口里刷新。"
}

jg_help() {
    cat <<EOF
酒馆一键部署工具 v$JIUGUAN_VERSION

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
  JIUGUAN_HOME                 自定义安装目录，默认：$HOME/jiuguan
  JIUGUAN_NPM_REGISTRY         自定义 npm registry
  JIUGUAN_SILLYTAVERN_REPO     自定义 SillyTavern Git 仓库或镜像
EOF
}