#!/usr/bin/env bash

JIUGUAN_VERSION="0.2.0"
JG_ST_REPO_DEFAULT="https://github.com/SillyTavern/SillyTavern.git"
JG_ST_BRANCH_DEFAULT="release"
JG_ST_VERIFIED_MIRRORS=(
    "https://ghfast.top/https://github.com/SillyTavern/SillyTavern.git"
)
JG_NPM_OFFICIAL_REGISTRY="https://registry.npmjs.org/"
JG_NPM_MIRROR_REGISTRY="https://registry.npmmirror.com"
JG_NPM_REGISTRY_ARGS=()

jg_info() { printf '[信息] %s\n' "$*"; }
jg_success() { printf '[完成] %s\n' "$*"; }
jg_warn() { printf '[提醒] %s\n' "$*"; }
jg_die() { printf '[错误] %s\n' "$*" >&2; exit 1; }

jg_load_paths() {
    JG_ROOT="${JIUGUAN_HOME:-$HOME/214769SillyTavern}"
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

jg_run_apt_get() {
    if jg_is_termux; then
        env DEBIAN_FRONTEND=noninteractive apt-get "$@"
    else
        jg_use_sudo env DEBIAN_FRONTEND=noninteractive apt-get "$@"
    fi
}

jg_apt_update() {
    jg_run_apt_get update
}

jg_apt_install() {
    jg_run_apt_get install -y \
        -o Dpkg::Options::="--force-confdef" \
        -o Dpkg::Options::="--force-confold" \
        "$@"
}

jg_apt_full_upgrade() {
    jg_run_apt_get full-upgrade -y \
        -o Dpkg::Options::="--force-confdef" \
        -o Dpkg::Options::="--force-confold"
}

jg_termux_prepare_packages() {
    jg_info "检测到 Termux。请确认使用的是 F-Droid 版 Termux。"
    jg_info "准备 Termux 基础环境，避免只更新 curl 导致底层库不匹配。"
    jg_apt_update || jg_die "Termux 更新软件源失败。请切换网络或更换 Termux 镜像源后重试。"
    jg_apt_full_upgrade || jg_die "Termux 自动升级基础包失败。请重新打开 Termux 后再运行：jiuguan install"
    jg_apt_install git nodejs curl wget ca-certificates tar gzip || jg_die "Termux 依赖安装失败。请重新打开 Termux 后再运行：jiuguan install"
    hash -r 2>/dev/null || true

    if jg_command_exists curl && ! curl --version >/dev/null 2>&1; then
        jg_warn "curl 仍无法运行，尝试重装相关基础库。"
        jg_run_apt_get install --reinstall -y \
            -o Dpkg::Options::="--force-confdef" \
            -o Dpkg::Options::="--force-confold" \
            curl libcurl openssl libngtcp2 ca-certificates >/dev/null 2>&1 || true
        hash -r 2>/dev/null || true
    fi

    if ! { jg_command_exists curl && curl --version >/dev/null 2>&1; } &&
        ! { jg_command_exists wget && wget --version >/dev/null 2>&1; }; then
        jg_die "Termux 的 curl/wget 仍无法运行。请重新打开 Termux，先执行 pkg upgrade，再运行：jiuguan install"
    fi

    if jg_command_exists termux-setup-storage; then
        jg_info "如需从手机存储导入角色或备份，可稍后运行 termux-setup-storage。"
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
    jg_apt_update
    jg_apt_install git curl ca-certificates tar gzip nodejs npm
    return 0
}

jg_node_version() {
    if ! jg_command_exists node; then
        return 127
    fi

    local output status
    set +e
    output="$(node --version 2>&1)"
    status=$?
    set -e

    if [[ "$status" -ne 0 ]]; then
        printf '%s\n' "$output" >&2
        return "$status"
    fi

    printf '%s\n' "$output"
}

jg_node_major() {
    local version
    if ! version="$(jg_node_version)"; then
        echo 0
        return 1
    fi

    printf '%s\n' "$version" | sed 's/^v//' | awk -F. '{print $1}'
}

jg_verify_node18() {
    local major node_status
    set +e
    major="$(jg_node_major)"
    node_status=$?
    set -e

    if [[ "$node_status" -eq 0 && "$major" =~ ^[0-9]+$ && "$major" -ge 18 ]]; then
        return 0
    fi

    return 1
}

jg_ensure_node18() {
    local major node_status
    set +e
    major="$(jg_node_major)"
    node_status=$?
    set -e

    if [[ "$node_status" -eq 0 && "$major" =~ ^[0-9]+$ && "$major" -ge 18 ]]; then
        return
    fi

    if jg_is_termux; then
        if [[ "$node_status" -ne 0 ]]; then
            jg_warn "当前 Termux 的 Node.js 无法运行，尝试重装 nodejs。"
        else
            jg_warn "当前 Node.js 版本较旧，尝试通过 Termux apt 更新。"
        fi

        jg_apt_install nodejs || jg_die "Node.js 安装失败。请运行 apt update && apt install nodejs 后重试。"

        set +e
        major="$(jg_node_major)"
        node_status=$?
        set -e

        if [[ "$node_status" -ne 0 ]]; then
            jg_die "Node.js 在当前 Termux 环境中安装成功但无法运行。MuMu 模拟器可能不兼容当前 Termux nodejs 包；建议换 F-Droid Termux 真机测试，或在 Termux 中尝试：pkg install nodejs-lts"
        fi

        if [[ "$major" =~ ^[0-9]+$ && "$major" -ge 18 ]]; then
            return
        fi

        jg_die "Node.js 版本仍过旧。请运行 apt update && apt install nodejs 后重试。"
    fi

    if jg_is_macos; then
        jg_install_homebrew_if_needed
        brew install node || brew upgrade node || jg_die "Node.js 安装失败。请访问 https://nodejs.org/ 手动安装 LTS 版本。"
        jg_verify_node18 || jg_die "Node.js 安装后仍不是 18 或更新版本。请重新打开终端后运行：jiuguan install"
        return
    fi

    if jg_is_linux && jg_command_exists apt-get; then
        jg_warn "系统自带 Node.js 版本较旧，准备使用 NodeSource 安装 LTS 版本。"
        curl --fail --location --show-error --retry 3 --connect-timeout 15 https://deb.nodesource.com/setup_lts.x | jg_use_sudo bash - || jg_die "NodeSource 配置失败。请手动安装 Node.js 18 或更新版本。"
        jg_apt_install nodejs
        jg_verify_node18 || jg_die "Node.js 安装后仍不是 18 或更新版本。请重新打开终端后运行：jiuguan install"
        return
    fi

    jg_die "Node.js 版本过旧。请手动安装 Node.js 18 或更新版本后重试。"
}

jg_ensure_dependencies() {
    jg_info "检查 Git、Node.js 和 npm。"

    if jg_is_termux; then
        jg_termux_prepare_packages
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

    jg_info "检测较快的 npm 下载源。"
    if npm ping --registry "$JG_NPM_MIRROR_REGISTRY" --fetch-retries=1 --fetch-timeout=8000 >/dev/null 2>&1; then
        jg_info "使用 npmmirror 安装 npm 依赖。"
        JG_NPM_REGISTRY_ARGS=(--registry "$JG_NPM_MIRROR_REGISTRY")
        return
    fi

    jg_warn "npmmirror 暂时不可用，改用 npm 官方源。"
    npm ping --registry "$JG_NPM_OFFICIAL_REGISTRY" --fetch-retries=1 --fetch-timeout=8000 >/dev/null 2>&1 ||
        jg_die "npmmirror 和 npm 官方源都无法访问。请检查网络或代理后重试：jiuguan install"
}

jg_remote_branch_commit() {
    local repo="$1"
    local branch="$2"
    local output
    output="$(git -c http.version=HTTP/1.1 -c http.lowSpeedLimit=1024 -c http.lowSpeedTime=15 \
        ls-remote "$repo" "refs/heads/$branch" 2>/dev/null)" || return 1
    printf '%s\n' "$output" | awk 'NR == 1 && $1 ~ /^[0-9a-fA-F]{40}$/ { print tolower($1) }'
}

jg_repo_candidates() {
    local custom_repo="${JIUGUAN_SILLYTAVERN_REPO:-}"
    local custom_branch="${JIUGUAN_SILLYTAVERN_BRANCH:-}"
    local official_commit="" mirror mirror_commit

    if [[ -n "$custom_repo" ]]; then
        printf '%s|%s||2|自定义源\n' "$custom_repo" "$custom_branch"
    fi

    official_commit="$(jg_remote_branch_commit "$JG_ST_REPO_DEFAULT" "$JG_ST_BRANCH_DEFAULT" || true)"
    if [[ -n "$official_commit" ]]; then
        for mirror in "${JG_ST_VERIFIED_MIRRORS[@]}"; do
            mirror_commit="$(jg_remote_branch_commit "$mirror" "$JG_ST_BRANCH_DEFAULT" || true)"
            if [[ -n "$mirror_commit" && "$mirror_commit" == "$official_commit" ]]; then
                jg_success "加速源已通过官方提交校验：${official_commit:0:8}" >&2
                printf '%s|%s|%s|2|已校验加速源\n' "$mirror" "$JG_ST_BRANCH_DEFAULT" "$official_commit"
            elif [[ -n "$mirror_commit" ]]; then
                jg_warn "加速源版本与官方不一致，已跳过：$mirror" >&2
            fi
        done
    else
        jg_warn "无法取得官方提交哈希，本次不使用第三方加速源。" >&2
    fi

    if [[ -z "$custom_repo" || "$custom_repo" != "$JG_ST_REPO_DEFAULT" ]]; then
        printf '%s|%s|%s|1|官方源\n' "$JG_ST_REPO_DEFAULT" "$JG_ST_BRANCH_DEFAULT" "$official_commit"
    fi
}

jg_clone_sillytavern() {
    local repo="$1" branch="$2" expected="$3" attempts="$4" label="$5" destination="$6"
    local attempt actual
    local git_args=(-c http.version=HTTP/1.1 -c http.lowSpeedLimit=1024 -c http.lowSpeedTime=45 \
        clone --depth 1 --single-branch)
    [[ -n "$branch" ]] && git_args+=(--branch "$branch")

    for ((attempt = 1; attempt <= attempts; attempt++)); do
        [[ -e "$destination" ]] && jg_safe_rm_rf "$destination"
        jg_info "使用${label}拉取（第 $attempt/$attempts 次）：$repo"
        if git "${git_args[@]}" "$repo" "$destination" && [[ -f "$destination/package.json" ]]; then
            if [[ -n "$expected" ]]; then
                actual="$(git -C "$destination" rev-parse HEAD 2>/dev/null || true)"
                if [[ "$actual" != "$expected" ]]; then
                    jg_warn "下载结果未通过提交校验，已删除并切换来源。"
                    jg_safe_rm_rf "$destination"
                    return 1
                fi
                if [[ "$repo" != "$JG_ST_REPO_DEFAULT" ]]; then
                    git -C "$destination" remote set-url origin "$JG_ST_REPO_DEFAULT" || {
                        jg_warn "无法把长期更新地址切回官方仓库，将改用下一个来源。"
                        jg_safe_rm_rf "$destination"
                        return 1
                    }
                fi
            fi
            return 0
        fi
        jg_warn "拉取中断，将自动清理临时目录后重试。"
    done

    [[ -e "$destination" ]] && jg_safe_rm_rf "$destination"
    return 1
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

    if [[ -d "$JG_ST/.git" && ! -f "$JG_ST/package.json" ]]; then
        jg_warn "发现上次下载中断留下的不完整目录，正在自动清理。"
        jg_safe_rm_rf "$JG_ST"
    fi

    if [[ ! -e "$JG_ST" ]]; then
        local cloned=0 repo branch expected attempts label
        local download_path="${JG_ST}.download"
        while IFS='|' read -r repo branch expected attempts label; do
            [[ -n "$repo" ]] || continue
            if jg_clone_sillytavern "$repo" "$branch" "$expected" "$attempts" "$label" "$download_path"; then
                mv "$download_path" "$JG_ST"
                cloned=1
                break
            fi
            jg_warn "这个来源拉取失败，尝试下一个来源。"
        done < <(jg_repo_candidates)

        [[ "$cloned" -eq 1 ]] || jg_die "SillyTavern 自动重试后仍拉取失败。请切换网络，或设置 JIUGUAN_SILLYTAVERN_REPO 后重试：jiuguan install"
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
        rm -f -- "$JG_PID"
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
    printf '214769SillyTavern：v%s\n' "$JIUGUAN_VERSION"
    printf '安装目录：%s\n' "$JG_ROOT"

    local node_version
    if node_version="$(jg_node_version 2>/dev/null)"; then
        printf 'Node.js：%s\n' "$node_version"
    elif jg_command_exists node; then
        printf 'Node.js：已安装但无法运行\n'
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
    if tar -tzf "$backup_path" | awk '
        $0 ~ /^\/|(^|\/)\.\.(\/|$)/ { bad=1 }
        END { exit bad ? 1 : 0 }
    '; then
        tar -xzf "$backup_path" -C "$stage"
    else
        rm -rf -- "$stage"
        jg_die "备份文件里包含不安全路径，已取消恢复：$backup_path"
    fi

    for item in data public/user config.yaml config.conf plugins; do
        source="$stage/$item"
        target="$JG_ST/$item"
        if [[ -e "$source" ]]; then
            case "$target" in
                "$JG_ST"/*) [[ -e "$target" ]] && jg_safe_rm_rf "$target" ;;
                *) jg_die "恢复目标路径异常：$target" ;;
            esac
            mkdir -p "$(dirname "$target")"
            cp -a "$source" "$target"
        fi
    done

    rm -rf -- "$stage"
    jg_success "已恢复备份：$backup_path"
}


jg_raw_base_candidates() {
    local preferred="${1:-}"
    local default_base="https://cdn.jsdelivr.net/gh/21476xc/214769xc@main"
    local emitted=" " base
    for base in "$preferred" "$default_base" "https://fastly.jsdelivr.net/gh/21476xc/214769xc@main" "https://raw.githubusercontent.com/21476xc/214769xc/main"; do
        [[ -n "$base" ]] || continue
        case "$emitted" in
            *" $base "*) continue ;;
        esac
        printf '%s\n' "$base"
        emitted="$emitted$base "
    done
}

jg_download_tool_file() {
    local relative="$1"
    local destination="$2"
    local preferred="${3:-}"
    local base url
    JG_SELECTED_RAW_BASE=""

    while IFS= read -r base; do
        [[ -n "$base" ]] || continue
        url="$base/$relative"
        jg_info "下载 $url"
        if jg_command_exists curl && curl --fail --location --show-error --retry 2 --connect-timeout 10 --max-time 45 "$url" -o "$destination"; then
            JG_SELECTED_RAW_BASE="$base"
            return 0
        fi

        if jg_command_exists wget && wget -qO "$destination" --timeout=15 --tries=2 "$url"; then
            JG_SELECTED_RAW_BASE="$base"
            return 0
        fi

        jg_warn "下载失败，尝试备用源。"
    done < <(jg_raw_base_candidates "$preferred")

    return 1
}

jg_update_tool() {
    jg_init_dirs
    local raw_base="${JIUGUAN_RAW_BASE_URL:-}"
    if [[ -z "$raw_base" && -f "$JG_RAW_BASE_FILE" ]]; then
        raw_base="$(tr -d '\r\n' < "$JG_RAW_BASE_FILE")"
    fi

    if [[ -z "$raw_base" ]]; then
        jg_info "没有配置远程工具地址，跳过工具自身更新。"
        return
    fi

    local relative destination temp
    for relative in bin/jiuguan.sh lib/jiuguan.sh; do
        destination="$JG_TOOL/$relative"
        temp="$destination.tmp"
        jg_info "更新工具文件：$relative"
        jg_download_tool_file "$relative" "$temp" "$raw_base" || jg_die "下载 $relative 失败。请检查网络后重试。"
        if [[ -n "$JG_SELECTED_RAW_BASE" ]]; then
            raw_base="$JG_SELECTED_RAW_BASE"
        fi
        mv "$temp" "$destination"
    done
    printf '%s\n' "$raw_base" > "$JG_RAW_BASE_FILE"
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

    jg_backup

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
    local root_abs home_abs target_abs target_dir target_base
    [[ -n "$path" ]] || jg_die "拒绝删除空路径。"
    [[ -e "$path" || -L "$path" ]] || return 0

    root_abs="$(mkdir -p "$JG_ROOT" && cd -P "$JG_ROOT" && pwd)"
    home_abs="$(cd -P "$HOME" && pwd)"
    if [[ -d "$path" && ! -L "$path" ]]; then
        target_abs="$(cd -P "$path" && pwd)"
    else
        target_dir="$(dirname "$path")"
        target_base="$(basename "$path")"
        target_abs="$(cd -P "$target_dir" && printf '%s/%s\n' "$(pwd)" "$target_base")"
    fi

    case "$target_abs" in
        /|"$home_abs"|"$root_abs")
            jg_die "拒绝删除高风险路径：$target_abs"
            ;;
        "$root_abs"/*) ;;
        *) jg_die "拒绝删除安装目录外的路径：$target_abs" ;;
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


jg_remove_termux_auto_menu() {
    local bashrc="$HOME/.bashrc"
    [[ -f "$bashrc" ]] || return 0
    sed -i '/# 214769SillyTavern auto menu begin/,/# 214769SillyTavern auto menu end/d' "$bashrc" 2>/dev/null || true
}

jg_uninstall() {
    local delete_data="${1:-0}"
    jg_load_paths
    jg_stop

    local shim
    shim="$(jg_shim_path)"
    rm -f -- "$shim"
    if jg_is_termux; then
        jg_remove_termux_auto_menu
    fi

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


jg_menu_action() {
    local status
    set +e
    (
        set -e
        "$@"
    )
    status=$?
    set -e
    if [[ "$status" -ne 0 ]]; then
        jg_warn "操作没有完成，请查看上面的提示后重试。"
    fi
    return 0
}

jg_data_menu() {
    while true; do
        printf '\n用户数据\n'
        printf '%s\n' '----------------------------'
        printf '1. 备份用户数据\n'
        printf '2. 恢复最新备份\n'
        printf '0. 返回主菜单\n'
        printf '请输入数字：'
        IFS= read -r choice || return 0

        case "$choice" in
            1) jg_menu_action jg_backup ;;
            2) jg_menu_action jg_restore ;;
            0) return 0 ;;
            *) jg_warn "请输入 0 到 2 之间的数字。" ;;
        esac

        if [[ "$choice" != "0" ]]; then
            printf '\n按回车返回'
            IFS= read -r _ || return 0
        fi
    done
}

jg_uninstall_menu() {
    while true; do
        printf '\n卸载\n'
        printf '%s\n' '----------------------------'
        printf '1. 卸载管理工具，保留 SillyTavern 和备份\n'
        printf '2. 卸载并删除全部本地数据\n'
        printf '0. 返回主菜单\n'
        printf '请输入数字：'
        IFS= read -r choice || return 1

        case "$choice" in
            1)
                jg_uninstall 0
                return 0
                ;;
            2)
                jg_warn "这会删除 SillyTavern、本地数据、日志和备份。"
                printf '确认删除请输入 DELETE：'
                IFS= read -r confirm || return 1
                if [[ "$confirm" == "DELETE" ]]; then
                    jg_uninstall 1
                    return 0
                fi
                jg_warn "未输入 DELETE，已取消删除。"
                return 1
                ;;
            0) return 1 ;;
            *) jg_warn "请输入 0 到 2 之间的数字。" ;;
        esac
    done
}

jg_menu() {
    while true; do
        printf '\n214769SillyTavern 控制台 v%s\n' "$JIUGUAN_VERSION"
        printf '%s\n' '----------------------------'
        printf '1. 安装或修复 SillyTavern\n'
        printf '2. 启动 SillyTavern\n'
        printf '3. 停止 SillyTavern\n'
        printf '4. 重启 SillyTavern\n'
        printf '5. 查看状态和访问地址\n'
        printf '6. 查看最近日志\n'
        printf '7. 更新工具和 SillyTavern\n'
        printf '8. 备份/恢复用户数据\n'
        printf '9. 卸载\n'
        printf '0. 退出\n'
        printf '请输入数字：'
        IFS= read -r choice || return 0

        case "$choice" in
            1) jg_menu_action jg_install ;;
            2) jg_menu_action jg_start ;;
            3) jg_menu_action jg_stop ;;
            4) jg_menu_action jg_restart ;;
            5) jg_menu_action jg_status ;;
            6) jg_menu_action jg_logs 120 ;;
            7) jg_menu_action jg_update ;;
            8) jg_data_menu ;;
            9) if jg_uninstall_menu; then return 0; fi ;;
            0) return 0 ;;
            *) jg_warn "请输入 0 到 9 之间的数字。" ;;
        esac

        if [[ "$choice" != "0" ]]; then
            printf '\n按回车返回菜单'
            IFS= read -r _ || return 0
        fi
    done
}
jg_help() {
    cat <<EOF
214769SillyTavern v$JIUGUAN_VERSION

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
  JIUGUAN_HOME                 自定义安装目录，默认：$HOME/214769SillyTavern
  JIUGUAN_NPM_REGISTRY         自定义 npm registry
  JIUGUAN_SILLYTAVERN_REPO     自定义 SillyTavern Git 仓库或镜像
EOF
}
