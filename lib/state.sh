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
  awk '{print $1}' "$sf"
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

# Escape a string for embedding in a JSON string literal (double quotes).
_state_json_escape() {
  local s="$1"
  s="${s//\\/\\\\}"
  s="${s//\"/\\\"}"
  s="${s//	/\\t}"
  s="${s//$'\n'/\\n}"
  s="${s//$'\r'/\\r}"
  printf '%s' "$s"
}

# Print the per-realm state file for <name> (existence unchecked).
_state_realm_file() {
  local sdir
  sdir=$(dirname -- "${MANGOS_STATE_FILE:?MANGOS_STATE_FILE not set}")
  printf '%s/%s.state\n' "$sdir" "$1"
}

# state_list_realms — print the names of realms this installer knows
# about (derived from REALM_<name>_CORE keys in config.env).
state_list_realms() {
  local cf="${MANGOS_CONFIG_FILE:-}"
  [[ -n "$cf" ]] && [[ -f "$cf" ]] || return 0
  grep -oE '^REALM_[a-z0-9_]+_CORE=' "$cf" 2>/dev/null \
    | sed -E 's/^REALM_(.*)_CORE=$/\1/' \
    | sort -u
}

# state_json_write — atomically write ~mangos/mangos/.installer/state.json
# reflecting current config and state files. Printf-based; no jq.
state_json_write() {
  local root="${MANGOS_ROOT:-$MANGOS_DEFAULT_INSTALL_ROOT}"
  [[ -d "$root/.installer" ]] || return 0
  local out="$root/.installer/state.json"
  local tmp
  tmp=$(mktemp -- "${out}.XXXXXX")

  local sdir
  sdir=$(dirname -- "${MANGOS_STATE_FILE:?MANGOS_STATE_FILE not set}")
  local global_state="$sdir/global.state"

  local completed_globals
  completed_globals=$(awk '{print $1}' "$global_state" 2>/dev/null \
                       | sort -u | tr '\n' ',' | sed 's/,$//')

  {
    printf '{\n'
    printf '  "schema_version": 1,\n'
    printf '  "installer_version": "%s",\n' "$(_state_json_escape "${INSTALLER_VERSION:-unknown}")"
    printf '  "generated_at": "%s",\n' "$(date -u +'%Y-%m-%dT%H:%M:%SZ')"
    printf '  "global": {\n'
    printf '    "mangos_user": "%s",\n'    "$(_state_json_escape "${MANGOS_USER:-${MANGOS_DEFAULT_USER}}")"
    printf '    "install_root": "%s",\n'   "$(_state_json_escape "$root")"
    printf '    "openssl_prefix": "%s",\n' "$(_state_json_escape "${OPENSSL_PREFIX:-$root/opt/openssl-1.1}")"
    printf '    "db_mode": "%s",\n'        "$(_state_json_escape "${MANGOS_DB_MODE:-local}")"
    printf '    "db_host": "%s",\n'        "$(_state_json_escape "${MANGOS_DB_HOST:-localhost}")"
    printf '    "db_port": %s,\n'          "${MANGOS_DB_PORT:-3306}"
    printf '    "completed_phases": ['
    if [[ -n "$completed_globals" ]]; then
      local p first=1
      IFS=',' read -ra _phases <<< "$completed_globals"
      for p in "${_phases[@]}"; do
        (( first )) && first=0 || printf ','
        printf '"%s"' "$(_state_json_escape "$p")"
      done
    fi
    printf ']\n'
    printf '  },\n'

    printf '  "realms": ['
    local realms
    realms=$(state_list_realms)
    if [[ -n "$realms" ]]; then
      local first=1 r
      while IFS= read -r r; do
        (( first )) && first=0 || printf ','
        printf '\n'
        _state_json_realm_block "$r"
      done <<< "$realms"
      printf '\n  '
    fi
    printf ']\n'
    printf '}\n'
  } > "$tmp"

  mv -- "$tmp" "$out"
  chmod 0644 -- "$out"
  chown "${MANGOS_USER:-${MANGOS_DEFAULT_USER}}:${MANGOS_USER:-${MANGOS_DEFAULT_USER}}" -- "$out" 2>/dev/null || true
  log_debug "wrote $out"
}

# Private: emit one realm object into the state.json stream.
_state_json_realm_block() {
  local r="$1"
  local core   name   addr   port
  local db_auth db_char db_world ref installed_at last_updated status
  core=$(_kv_get         "${MANGOS_CONFIG_FILE}" "REALM_${r}_CORE")
  name=$(_kv_get         "${MANGOS_CONFIG_FILE}" "REALM_${r}_NAME")
  addr=$(_kv_get         "${MANGOS_CONFIG_FILE}" "REALM_${r}_ADDRESS")
  port=$(_kv_get         "${MANGOS_CONFIG_FILE}" "REALM_${r}_WORLD_PORT")
  db_auth=$(_kv_get      "${MANGOS_CONFIG_FILE}" "REALM_${r}_DB_AUTH")
  db_char=$(_kv_get      "${MANGOS_CONFIG_FILE}" "REALM_${r}_DB_CHAR")
  db_world=$(_kv_get     "${MANGOS_CONFIG_FILE}" "REALM_${r}_DB_WORLD")
  ref=$(_kv_get          "${MANGOS_CONFIG_FILE}" "REALM_${r}_MANGOS_REF")
  installed_at=$(_kv_get "${MANGOS_CONFIG_FILE}" "REALM_${r}_INSTALLED_AT")
  last_updated=$(_kv_get "${MANGOS_CONFIG_FILE}" "REALM_${r}_LAST_UPDATED")
  status=$(_kv_get       "${MANGOS_CONFIG_FILE}" "REALM_${r}_STATUS")

  local root="${MANGOS_ROOT:-$MANGOS_DEFAULT_INSTALL_ROOT}"
  local realm_dir="$root/$r"

  local realm_state_file
  realm_state_file=$(_state_realm_file "$r")
  local completed
  completed=$(awk '{print $1}' "$realm_state_file" 2>/dev/null | sort -u | tr '\n' ',' | sed 's/,$//')

  printf '    {\n'
  printf '      "name": "%s",\n'            "$(_state_json_escape "$r")"
  printf '      "core": "%s",\n'            "$(_state_json_escape "$core")"
  printf '      "mangos_ref": "%s",\n'      "$(_state_json_escape "$ref")"
  printf '      "world_port": %s,\n'        "${port:-0}"
  printf '      "realm_name": "%s",\n'      "$(_state_json_escape "$name")"
  printf '      "realm_address": "%s",\n'   "$(_state_json_escape "$addr")"
  printf '      "systemd_units": ["mangos-realmd", "mangos-mangosd@%s"],\n' \
         "$(_state_json_escape "$r")"
  printf '      "paths": {\n'
  printf '        "bin": "%s",\n'           "$(_state_json_escape "$realm_dir/bin")"
  printf '        "etc": "%s",\n'           "$(_state_json_escape "$realm_dir/etc")"
  printf '        "gamedata": "%s",\n'      "$(_state_json_escape "$realm_dir/gamedata")"
  printf '        "logs": "%s"\n'           "$(_state_json_escape "$realm_dir/logs")"
  printf '      },\n'
  printf '      "databases": {\n'
  printf '        "auth": "%s",\n'          "$(_state_json_escape "$db_auth")"
  printf '        "characters": "%s",\n'    "$(_state_json_escape "$db_char")"
  printf '        "world": "%s"\n'          "$(_state_json_escape "$db_world")"
  printf '      },\n'
  printf '      "status": "%s",\n'          "$(_state_json_escape "${status:-unknown}")"
  printf '      "installed_at": "%s",\n'    "$(_state_json_escape "$installed_at")"
  printf '      "last_updated_at": "%s",\n' "$(_state_json_escape "$last_updated")"
  printf '      "completed_phases": ['
  if [[ -n "$completed" ]]; then
    local p first=1
    IFS=',' read -ra _phases <<< "$completed"
    for p in "${_phases[@]}"; do
      (( first )) && first=0 || printf ','
      printf '"%s"' "$(_state_json_escape "$p")"
    done
  fi
  printf ']\n'
  printf '    }'
}
