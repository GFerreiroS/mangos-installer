#!/usr/bin/env bash
# mangos-installer — logging primitives
# SPDX-License-Identifier: GPL-2.0-only
# See CLAUDE.md for design, README.md for usage
# shellcheck shell=bash
#
# Format: "YYYY-MM-DD HH:MM:SS [LEVEL] [phase] message"
# Logs go to MANGOS_LOG_FILE (and also to stderr when MANGOS_LOG_LEVEL=debug).
# MANGOS_CURRENT_PHASE is the running phase name; defaults to "bootstrap".

_log_write() {
  local level="$1"
  shift
  local msg="$*"
  local ts
  ts=$(date -u +'%Y-%m-%d %H:%M:%S')
  local phase="${MANGOS_CURRENT_PHASE:-bootstrap}"
  local line
  line=$(printf '%s [%s] [%s] %s' "$ts" "$level" "$phase" "$msg")
  local lf="${MANGOS_LOG_FILE:-}"
  if [[ -n "$lf" ]]; then
    if [[ -w "$lf" ]] || { [[ ! -e "$lf" ]] && [[ -w "$(dirname -- "$lf")" ]]; }; then
      printf '%s\n' "$line" >> "$lf" 2>/dev/null || true
    fi
  fi
  if [[ "${MANGOS_LOG_LEVEL:-info}" == "debug" ]]; then
    printf '%s\n' "$line" >&2
  fi
}

log_debug() { [[ "${MANGOS_LOG_LEVEL:-info}" == "debug" ]] && _log_write DEBUG "$*"; return 0; }
log_info()  { _log_write INFO  "$*"; }
log_warn()  { _log_write WARN  "$*"; }
log_error() { _log_write ERROR "$*"; }

die() {
  local msg="${1:-unknown error}"
  local exit_code="${2:-1}"
  log_error "$msg"
  if declare -F ui_status_fail >/dev/null 2>&1; then
    ui_status_fail "$msg"
    declare -F ui_print_recent_log >/dev/null 2>&1 && ui_print_recent_log
  else
    printf 'ERROR: %s\n' "$msg" >&2
  fi
  exit "$exit_code"
}
