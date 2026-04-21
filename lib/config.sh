#!/usr/bin/env bash
# mangos-installer — flat env-style config file (sourced as bash)
# SPDX-License-Identifier: GPL-2.0-only
# See CLAUDE.md for design, README.md for usage
# shellcheck shell=bash
#
# config.env is a list of KEY="value" lines. Sourced by this lib (and by
# the runner) to repopulate state across re-runs. Realm-scoped keys use
# the convention REALM_<name>_<KEY>.

config_load() {
  local cf="${MANGOS_CONFIG_FILE:-}"
  [[ -n "$cf" ]] && [[ -f "$cf" ]] || return 0
  # Source via a filtered temp file: skip keys that are already declared
  # readonly (e.g. INSTALLER_VERSION from constants.sh) so sourcing does
  # not abort on "readonly variable" errors when re-running the installer.
  local tmp key line
  tmp=$(mktemp)
  while IFS= read -r line || [[ -n "$line" ]]; do
    key="${line%%=*}"
    if declare -p "$key" 2>/dev/null | grep -q ' -[[:alpha:]]*r'; then
      continue
    fi
    printf '%s\n' "$line" >> "$tmp"
  done < "$cf"
  set -a
  # shellcheck disable=SC1090
  . "$tmp"
  set +a
  rm -f -- "$tmp"
  log_debug "loaded config from $cf"
}

# _kv_set <file> <key> <value>  — atomic rewrite that replaces any existing
# line for <key> and appends the new one. Escapes characters that would
# otherwise be interpreted when sourced.
_kv_set() {
  local file="$1" key="$2" value="$3"
  mkdir -p -- "$(dirname -- "$file")"
  local tmp
  tmp=$(mktemp -- "${file}.XXXXXX")
  if [[ -f "$file" ]]; then
    grep -v -- "^${key}=" "$file" > "$tmp" || true
  fi
  local v="$value"
  v="${v//\\/\\\\}"
  v="${v//\"/\\\"}"
  v="${v//\$/\\\$}"
  v="${v//\`/\\\`}"
  printf '%s="%s"\n' "$key" "$v" >> "$tmp"
  mv -- "$tmp" "$file"
}

# _kv_get <file> <key>  — print the most recent value, empty if unset.
_kv_get() {
  local file="$1" key="$2"
  [[ -f "$file" ]] || return 0
  local line
  line=$(grep -- "^${key}=" "$file" | tail -n 1) || true
  [[ -z "$line" ]] && return 0
  local val="${line#"${key}="}"
  if [[ "${val:0:1}" == '"' ]] && [[ "${val: -1}" == '"' ]]; then
    val="${val:1:${#val}-2}"
  fi
  val="${val//\\\"/\"}"
  val="${val//\\\$/\$}"
  val="${val//\\\`/\`}"
  val="${val//\\\\/\\}"
  printf '%s\n' "$val"
}

config_set() { _kv_set "${MANGOS_CONFIG_FILE:?MANGOS_CONFIG_FILE not set}" "$1" "$2"; }
config_get() { _kv_get "${MANGOS_CONFIG_FILE:?MANGOS_CONFIG_FILE not set}" "$1"; }

# config_hydrate_realm <name> — copy REALM_<name>_<suffix> values into
# MANGOS_REALM_<suffix> globals. Lets phases address realm vars by a stable
# name regardless of which realm is currently active.
config_hydrate_realm() {
  local r="$1"
  [[ -n "$r" ]] || return 1
  local key suffix
  for suffix in CORE NAME ADDRESS WORLD_PORT DB_AUTH DB_CHAR DB_WORLD MANGOS_REF INSTALLED_AT LAST_UPDATED STATUS; do
    key="REALM_${r}_${suffix}"
    if [[ -n "${!key:-}" ]]; then
      # REALM_<r>_NAME holds the display name in this project; expose it
      # through MANGOS_REALM_DISPLAY to avoid clashing with the basename var.
      case "$suffix" in
        NAME) export MANGOS_REALM_DISPLAY="${!key}" ;;
        *)    export "MANGOS_REALM_${suffix}=${!key}" ;;
      esac
    fi
  done
  export MANGOS_REALM_NAME="$r"
  log_debug "hydrated realm vars for '$r'"
}
