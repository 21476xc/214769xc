#!/usr/bin/env bash
set -Eeuo pipefail

RAW_BASE_URL="${JIUGUAN_RAW_BASE_URL:-https://raw.githubusercontent.com/your-name/jiuguan/main}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOCAL_INSTALLER="$SCRIPT_DIR/scripts/install.sh"

if [[ -f "$LOCAL_INSTALLER" ]]; then
    exec bash "$LOCAL_INSTALLER" --raw-base-url "$RAW_BASE_URL" "$@"
fi

TEMP_FILE="${TMPDIR:-/tmp}/jiuguan-install.sh"
if command -v curl >/dev/null 2>&1; then
    curl -fsSL "$RAW_BASE_URL/scripts/install.sh" -o "$TEMP_FILE"
elif command -v wget >/dev/null 2>&1; then
    wget -qO "$TEMP_FILE" "$RAW_BASE_URL/scripts/install.sh"
else
    printf '[错误] 系统缺少 curl/wget，无法下载安装脚本。\n' >&2
    exit 1
fi

exec bash "$TEMP_FILE" --raw-base-url "$RAW_BASE_URL" "$@"