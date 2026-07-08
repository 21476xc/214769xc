#!/usr/bin/env bash
set -Eeuo pipefail

RAW_BASE_URL="${JIUGUAN_RAW_BASE_URL:-}"
INSTALL_ROOT="${JIUGUAN_HOME:-$HOME/214769SillyTavern}"
SKIP_INSTALL=0

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
    RAW_BASE_URL="https://raw.githubusercontent.com/21476xc/214769xc/main"
fi

install_info() { printf '[信息] %s\n' "$*"; }
install_success() { printf '[完成] %s\n' "$*"; }
install_die() { printf '[错误] %s\n' "$*" >&2; exit 1; }

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

    install_info "下载 $relative"
    if command -v curl >/dev/null 2>&1; then
        curl --fail --location --show-error --retry 3 --connect-timeout 15 "$RAW_BASE_URL/$relative" -o "$destination"
    elif command -v wget >/dev/null 2>&1; then
        wget -qO "$destination" "$RAW_BASE_URL/$relative"
    else
        install_die "系统缺少 curl/wget，无法下载工具文件。请先安装 curl 后重试。"
    fi
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

if [[ -n "${TERMUX_VERSION:-}" || -d "/data/data/com.termux/files/usr" ]]; then
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
    "$BIN_DIR/jiuguan.sh" install
fi

install_success "全部完成。常用命令：jiuguan start / jiuguan status / jiuguan update"