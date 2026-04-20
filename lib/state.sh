#!/usr/bin/env bash
# mangos-installer — phase completion tracking
# SPDX-License-Identifier: GPL-2.0-only
# See CLAUDE.md for design, README.md for usage
# shellcheck shell=bash
#
# Operates on $MANGOS_STATE_FILE. Each completed phase appends a line:
#   <phase-name> completed <ISO-8601-UTC>
# Two-tier: global state for phases 0–5, per-realm state for phases 6–14.
# The caller swaps MANGOS_STATE_FILE before invoking the per-realm phases.

state_mark_complete() {
  local phase="$1"
  local sf="${MANGOS_STATE_FILE:?MANGOS_STATE_FILE not set}"
  local ts
  ts=$(date -u +'%Y-%m-%dT%H:%M:%SZ')
  mkdir -p -- "$(dirname -- "$sf")"
  printf '%s completed %s\n' "$phase" "$ts" >> "$sf"
  log_debug "marked complete: $phase"
}

state_has_completed() {
  local phase="$1"
  local sf="${MANGOS_STATE_FILE:-}"
  [[ -n "$sf" ]] && [[ -f "$sf" ]] || return 1
  grep -q -- "^${phase} completed " "$sf"
}

state_list_completed() {
  local sf="${MANGOS_STATE_FILE:-}"
  [[ -n "$sf" ]] && [[ -f "$sf" ]] || return 0
  awk '{print $1}' -- "$sf"
}

state_reset() {
  local phase="$1"
  local sf="${MANGOS_STATE_FILE:-}"
  [[ -n "$sf" ]] && [[ -f "$sf" ]] || return 0
  local tmp
  tmp=$(mktemp -- "${sf}.XXXXXX")
  grep -v -- "^${phase} completed " "$sf" > "$tmp" || true
  mv -- "$tmp" "$sf"
  log_debug "reset: $phase"
}

# state_switch_to_realm [<name>] — point MANGOS_STATE_FILE at the per-realm
# state file for <name> (default: $MANGOS_REALM_NAME). Used by the flow to
# transition from global (phases 0–5) to per-realm (phases 6–14).
state_switch_to_realm() {
  local realm="${1:-${MANGOS_REALM_NAME:-}}"
  [[ -n "$realm" ]] || die "state_switch_to_realm: no realm (set MANGOS_REALM_NAME or pass an arg)"
  local sdir
  sdir=$(dirname -- "${MANGOS_STATE_FILE:?MANGOS_STATE_FILE not set}")
  MANGOS_STATE_FILE="$sdir/${realm}.state"
  export MANGOS_STATE_FILE
  mkdir -p -- "$sdir"
  log_info "state file switched to per-realm: $MANGOS_STATE_FILE"
}

# state_switch_to_global — return MANGOS_STATE_FILE to the global file.
state_switch_to_global() {
  local sdir
  sdir=$(dirname -- "${MANGOS_STATE_FILE:?MANGOS_STATE_FILE not set}")
  MANGOS_STATE_FILE="$sdir/global.state"
  export MANGOS_STATE_FILE
  log_info "state file switched to global: $MANGOS_STATE_FILE"
}
