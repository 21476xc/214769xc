#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TOOL_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
LIB_PATH="$TOOL_ROOT/lib/jiuguan.sh"

if [[ ! -f "$LIB_PATH" && -f "$TOOL_ROOT/../lib/jiuguan.sh" ]]; then
    LIB_PATH="$TOOL_ROOT/../lib/jiuguan.sh"
fi

# shellcheck source=../lib/jiuguan.sh
source "$LIB_PATH"

command_name="${1:-help}"
if [[ $# -gt 0 ]]; then
    shift
fi

case "$command_name" in
    install) jg_install "$@" ;;
    update) jg_update "$@" ;;
    start) jg_start "$@" ;;
    stop) jg_stop "$@" ;;
    restart) jg_restart "$@" ;;
    status) jg_status "$@" ;;
    logs) jg_logs "$@" ;;
    backup) jg_backup "$@" >/dev/null ;;
    restore) jg_restore "$@" ;;
    uninstall)
        delete_data=0
        if [[ " ${*:-} " == *" --delete-data "* ]]; then
            delete_data=1
        fi
        jg_uninstall "$delete_data"
        ;;
    help|--help|-h) jg_help ;;
    *)
        jg_warn "未知命令：$command_name"
        jg_help
        exit 2
        ;;
esac