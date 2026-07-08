#!/usr/bin/env bash
set -Eeuo pipefail

DEFAULT_RAW_BASE_URL="https://raw.githubusercontent.com/21476xc/214769xc/main"
RAW_BASE_URL="${JIUGUAN_RAW_BASE_URL:-$DEFAULT_RAW_BASE_URL}"
RAW_BASE_FALLBACK_URLS=(
    "https://cdn.jsdelivr.net/gh/21476xc/214769xc@main"
    "https://fastly.jsdelivr.net/gh/21476xc/214769xc@main"
)
SCRIPT_PATH="${BASH_SOURCE[0]:-}"

if [[ -n "$SCRIPT_PATH" && "$SCRIPT_PATH" != "bash" && "$SCRIPT_PATH" != "-" ]]; then
    SCRIPT_DIR="$(cd "$(dirname "$SCRIPT_PATH")" && pwd)"
    LOCAL_INSTALLER="$SCRIPT_DIR/scripts/install.sh"
else
    SCRIPT_DIR=""
    LOCAL_INSTALLER=""
fi

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
        printf '[信息] 下载 %s\n' "$url"
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
            printf '[错误] 系统缺少 curl/wget，无法下载安装脚本。\n' >&2
            return 1
        fi
        printf '[提醒] 下载失败，尝试备用源。\n' >&2
    done < <(raw_base_candidates)

    printf '[错误] 所有下载源都失败了，请稍后重试或切换网络。\n' >&2
    return 1
}

if [[ -n "$LOCAL_INSTALLER" && -f "$LOCAL_INSTALLER" ]]; then
    exec bash "$LOCAL_INSTALLER" --raw-base-url "$RAW_BASE_URL" "$@"
fi

TEMP_FILE="${TMPDIR:-/tmp}/jiuguan-install.sh"
download_file "scripts/install.sh" "$TEMP_FILE"
exec bash "$TEMP_FILE" --raw-base-url "$RAW_BASE_URL" "$@"