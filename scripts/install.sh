#!/usr/bin/env bash
set -Eeuo pipefail

DEFAULT_RAW_BASE_URL="https://raw.githubusercontent.com/21476xc/214769xc/main"
RAW_BASE_URL="${JIUGUAN_RAW_BASE_URL:-}"
INSTALL_ROOT="${JIUGUAN_HOME:-$HOME/214769SillyTavern}"
SKIP_INSTALL=0
RAW_BASE_FALLBACK_URLS=(
    "https://cdn.jsdelivr.net/gh/21476xc/214769xc@main"
    "https://fastly.jsdelivr.net/gh/21476xc/214769xc@main"
)

while [[ $# -gt 0 ]]; do
    case "$1" in
        --raw-base-url)
            RAW_BASE_URL="${2:-}"
            shift 2
            ;;
        --install-root)
            INSTALL_ROOT="${2:-}"
            shift 2
            ;;
        --skip-install)
            SKIP_INSTALL=1
            shift
            ;;
        *)
            printf '[错误] 未知参数：%s\n' "$1" >&2
            exit 2
            ;;
    esac
done

if [[ -z "$RAW_BASE_URL" ]]; then
    RAW_BASE_URL="$DEFAULT_RAW_BASE_URL"
fi

install_info() { printf '[信息] %s\n' "$*"; }
install_success() { printf '[完成] %s\n' "$*"; }
install_warn() { printf '[提醒] %s\n' "$*"; }
install_die() { printf '[错误] %s\n' "$*" >&2; exit 1; }

raw_base_candidates() {
    local emitted=" " base
    for base in "$RAW_BASE_URL" "$DEFAULT_RAW_BASE_URL" "${RAW_BASE_FALLBACK_URLS[@]}"; do
        [[ -n "$base" ]] || continue
        case "$emitted" in
            *" $base "*) continue ;;
        esac
        printf '%s\n' "$base"
        emitted="$emitted$base "
    done
}

download_file() {
    local relative="$1"
    local destination="$2"
    local base url

    while IFS= read -r base; do
        [[ -n "$base" ]] || continue
        url="$base/$relative"
        install_info "下载 $url"
        if command -v curl >/dev/null 2>&1; then
            if curl --fail --location --show-error --retry 3 --connect-timeout 15 "$url" -o "$destination"; then
                RAW_BASE_URL="$base"
                return 0
            fi
        elif command -v wget >/dev/null 2>&1; then
            if wget -qO "$destination" "$url"; then
                RAW_BASE_URL="$base"
                return 0
            fi
        else
            install_die "系统缺少 curl/wget，无法下载工具文件。请先安装 curl 后重试。"
        fi
        install_warn "下载失败，尝试备用源。"
    done < <(raw_base_candidates)

    install_die "所有下载源都失败了，请稍后重试或切换网络。"
}

copy_or_download() {
    local relative="$1"
    local destination="$2"
    local script_dir repo_root candidate

    script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    repo_root="$(cd "$script_dir/.." && pwd)"

    for candidate in "$repo_root/$relative" "$script_dir/$relative"; do
        if [[ -f "$candidate" ]]; then
            cp "$candidate" "$destination"
            return
        fi
    done

    download_file "$relative" "$destination"
}

is_termux() {
    [[ -n "${TERMUX_VERSION:-}" ]] || [[ -d "/data/data/com.termux/files/usr" ]]
}

install_termux_auto_menu() {
    if ! is_termux; then
        return
    fi

    local bashrc="$HOME/.bashrc"
    local marker="# 214769SillyTavern auto menu begin"
    if [[ -f "$bashrc" ]] && grep -Fq "$marker" "$bashrc"; then
        return
    fi

    cat >> "$bashrc" <<'EOF'

# 214769SillyTavern auto menu begin
if [[ $- == *i* ]] && [[ -z "${JIUGUAN_DISABLE_AUTO_MENU:-}" ]] && [[ -z "${JIUGUAN_MENU_ACTIVE:-}" ]] && command -v jiuguan >/dev/null 2>&1; then
    export JIUGUAN_MENU_ACTIVE=1
    jiuguan menu
    unset JIUGUAN_MENU_ACTIVE
fi
# 214769SillyTavern auto menu end
EOF
    install_info "已设置：下次打开 Termux 会自动进入数字控制台。"
}

case "$(uname -s)" in
    Linux|Darwin) ;;
    *) install_die "暂不支持当前系统：$(uname -s)。" ;;
esac

TOOL_ROOT="$INSTALL_ROOT/.jiuguan-tool"
BIN_DIR="$TOOL_ROOT/bin"
LIB_DIR="$TOOL_ROOT/lib"
mkdir -p "$BIN_DIR" "$LIB_DIR"

copy_or_download "bin/jiuguan.sh" "$BIN_DIR/jiuguan.sh"
copy_or_download "lib/jiuguan.sh" "$LIB_DIR/jiuguan.sh"
printf '%s\n' "$RAW_BASE_URL" > "$TOOL_ROOT/raw-base-url.txt"
chmod +x "$BIN_DIR/jiuguan.sh"

if is_termux; then
    SHIM_DIR="${PREFIX:-/data/data/com.termux/files/usr}/bin"
else
    SHIM_DIR="$HOME/.local/bin"
fi
mkdir -p "$SHIM_DIR"
SHIM_PATH="$SHIM_DIR/jiuguan"
cat > "$SHIM_PATH" <<EOF
#!/usr/bin/env bash
exec "$BIN_DIR/jiuguan.sh" "\$@"
EOF
chmod +x "$SHIM_PATH"
install_termux_auto_menu

if [[ ":$PATH:" != *":$SHIM_DIR:"* ]]; then
    PROFILE_LINE="export PATH=\"$SHIM_DIR:\$PATH\""
    for profile in "$HOME/.profile" "$HOME/.zprofile"; do
        if [[ ! -f "$profile" ]] || ! grep -Fq "$SHIM_DIR" "$profile"; then
            printf '\n# jiuguan command\n%s\n' "$PROFILE_LINE" >> "$profile"
        fi
    done
    export PATH="$SHIM_DIR:$PATH"
    install_info "已把 $SHIM_DIR 加入 PATH。新开的终端会自动生效。"
fi

install_success "214769SillyTavern 管理命令已安装：$SHIM_PATH"

if [[ "$SKIP_INSTALL" -ne 1 ]]; then
    install_info "开始安装或修复 SillyTavern。"
    if "$BIN_DIR/jiuguan.sh" install; then
        install_info "启动 SillyTavern 并显示访问地址。"
        "$BIN_DIR/jiuguan.sh" start || true
        "$BIN_DIR/jiuguan.sh" status || true
    else
        install_info "安装没有完成。下面进入数字控制台，你可以按 1 重试，或按 9 卸载。"
    fi

    install_info "进入数字控制台。"
    "$BIN_DIR/jiuguan.sh" menu
fi

install_success "全部完成。以后打开 Termux 会自动进入数字控制台；也可以手动运行 jiuguan。"