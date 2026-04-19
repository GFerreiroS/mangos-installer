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
