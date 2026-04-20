#!/usr/bin/env bash
# mangos-installer — add a second (or Nth) realm alongside existing ones
# SPDX-License-Identifier: GPL-2.0-only
# See CLAUDE.md for design, README.md for usage
# shellcheck shell=bash disable=SC2154
#
# Only multi-"zero" realms are supported right now (one/two/three cores
# are stubbed). We collect a fresh realm identity, pick the next free
# world port, register the realm in config.env, then run the per-realm
# phases 6-14 against a new <realm>.state file.

ui_print_banner "mangos installer ${INSTALLER_VERSION} — add a realm"

config_load

_add_realm_pick_port() {
  # Start at the highest existing port + 1, or 8086 if no prior realm
  # used a port. (Primary realm defaults to 8085.)
  local realms existing_max port used realm
  realms=$(state_list_realms)
  existing_max=0
  while IFS= read -r realm; do
    [[ -z "$realm" ]] && continue
    used=$(config_get "REALM_${realm}_WORLD_PORT")
    [[ -z "$used" ]] && continue
    (( used > existing_max )) && existing_max="$used"
  done <<< "$realms"
  if (( existing_max == 0 )); then
    port=8086
  else
    port=$(( existing_max + 1 ))
  fi
  printf '%d\n' "$port"
}

_add_realm_collect_identity() {
  local core realm_id display address port suggested_port

  core=$(ui_prompt_choice "MaNGOS core" "zero" "MANGOS_REALM_CORE" zero one two three)
  if ! core_supported "$core"; then
    die "core '$core' is not yet implemented — $(core_describe "$core")"
  fi

  # Prevent clobbering an existing realm.
  local existing
  existing=$(state_list_realms)
  while :; do
    realm_id=$(ui_prompt_text "new realm internal name (lowercase identifier)" "" "MANGOS_REALM_NAME")
    if [[ ! "$realm_id" =~ ^[a-z][a-z0-9_]{0,31}$ ]]; then
      ui_status_warn "invalid realm name '$realm_id' (need [a-z][a-z0-9_]{0,31})"
      unset MANGOS_REALM_NAME
      continue
    fi
    if printf '%s\n' "$existing" | grep -qx -- "$realm_id"; then
      ui_status_warn "realm '$realm_id' already exists"
      unset MANGOS_REALM_NAME
      [[ "${MANGOS_NONINTERACTIVE:-0}" == "1" ]] && die "realm '$realm_id' already exists"
      continue
    fi
    break
  done

  display=$(ui_prompt_text "realm display name" "$realm_id" "MANGOS_REALM_DISPLAY")
  address=$(ui_prompt_text "realm address (IP/hostname)" \
           "$(config_get "REALM_$(printf '%s\n' "$existing" | head -n 1)_ADDRESS")" \
           "MANGOS_REALM_ADDRESS")
  [[ -z "$address" ]] && address="127.0.0.1"

  suggested_port=$(_add_realm_pick_port)
  port=$(ui_prompt_text "world port" "$suggested_port" "MANGOS_REALM_WORLD_PORT")
  if [[ ! "$port" =~ ^[0-9]+$ ]] || (( port < 1024 || port > 65535 )); then
    die "invalid world port '$port'"
  fi
  # Reject a collision with an already-used port.
  local r other
  while IFS= read -r r; do
    [[ -z "$r" ]] && continue
    other=$(config_get "REALM_${r}_WORLD_PORT")
    if [[ "$other" == "$port" ]]; then
      die "world port $port is already used by realm '$r'"
    fi
  done <<< "$existing"

  export MANGOS_REALM_CORE="$core"
  export MANGOS_REALM_NAME="$realm_id"
  export MANGOS_REALM_DISPLAY="$display"
  export MANGOS_REALM_ADDRESS="$address"
  export MANGOS_REALM_WORLD_PORT="$port"
}

_add_realm_register() {
  local r="$MANGOS_REALM_NAME"
  # Realm index for DB naming. We scan existing REALM_*_DB_WORLD suffixes to
  # find the next free integer index.
  local i used existing_indexes=""
  while IFS= read -r other; do
    [[ -z "$other" ]] && continue
    local w
    w=$(config_get "REALM_${other}_DB_WORLD")
    # parse trailing digits: mangos_worldN
    if [[ "$w" =~ ([0-9]+)$ ]]; then
      existing_indexes+="${BASH_REMATCH[1]} "
    fi
  done < <(state_list_realms)
  local idx=0
  while true; do
    if [[ " $existing_indexes" != *" $idx "* ]]; then break; fi
    idx=$(( idx + 1 ))
  done

  config_set "REALM_${r}_CORE"         "$MANGOS_REALM_CORE"
  config_set "REALM_${r}_NAME"         "$MANGOS_REALM_DISPLAY"
  config_set "REALM_${r}_ADDRESS"      "$MANGOS_REALM_ADDRESS"
  config_set "REALM_${r}_WORLD_PORT"   "$MANGOS_REALM_WORLD_PORT"
  config_set "REALM_${r}_DB_AUTH"      "mangos_auth"
  config_set "REALM_${r}_DB_CHAR"      "mangos_character${idx}"
  config_set "REALM_${r}_DB_WORLD"     "mangos_world${idx}"
  config_set "REALM_${r}_INSTALLED_AT" "$(date -u +'%Y-%m-%dT%H:%M:%SZ')"
  config_set "REALM_${r}_STATUS"       "adding"
  config_set MANGOS_CURRENT_REALM      "$r"
  export MANGOS_REALM_DB_AUTH="mangos_auth"
  export MANGOS_REALM_DB_CHAR="mangos_character${idx}"
  export MANGOS_REALM_DB_WORLD="mangos_world${idx}"

  # Create the realm's directory tree (phase 1 only scaffolds the original
  # realm's dir; for add-realm we do just the per-realm subtree now).
  local realm_dir="$MANGOS_ROOT/$r"
  install -d -m 0755 -o "$MANGOS_DEFAULT_USER" -g "$MANGOS_DEFAULT_USER" -- \
    "$realm_dir" "$realm_dir/source" "$realm_dir/database" \
    "$realm_dir/build" "$realm_dir/bin" "$realm_dir/gamedata" \
    "$realm_dir/logs" "$realm_dir/backups"
  install -d -m 0750 -o "$MANGOS_DEFAULT_USER" -g "$MANGOS_DEFAULT_USER" -- \
    "$realm_dir/etc"

  ui_status_ok "realm '$r' registered (world port $MANGOS_REALM_WORLD_PORT, db index $idx)"
}

_add_realm_run_phases() {
  state_switch_to_realm "$MANGOS_REALM_NAME"

  local p num fn
  for p in \
      phase-06-fetch-sources \
      phase-07-db-schemas \
      phase-08-build \
      phase-09-install-binaries \
      phase-10-configs \
      phase-11-gamedata-prep \
      phase-12-gamedata-extract \
      phase-13-systemd \
      phase-14-smoke ; do
    # shellcheck disable=SC1090
    . "$MANGOS_INSTALLER_DIR/phases/${p}.sh"
    num="${p#phase-}"
    num="${num%%-*}"
    fn="run_phase_${num}"
    "$fn"
    state_json_write || true
  done
}

_add_realm_gamedata_hint() {
  # For the second realm the operator may want to reuse the already-
  # extracted gamedata from the primary realm. Warn up front so they know
  # they can stop and symlink, then re-run.
  local existing first_realm_gd
  existing=$(state_list_realms | grep -vx -- "$MANGOS_REALM_NAME" | head -n 1)
  [[ -z "$existing" ]] && return 0
  first_realm_gd="$MANGOS_ROOT/$existing/gamedata"
  if [[ -d "$first_realm_gd/maps" ]]; then
    ui_status_info ""
    ui_status_info "tip: the existing realm '$existing' already has extracted gamedata."
    ui_status_info "     you can reuse it by stopping here and symlinking dbc/ maps/ vmaps/"
    ui_status_info "     mmaps/ Data/ from $first_realm_gd into"
    ui_status_info "     $MANGOS_ROOT/$MANGOS_REALM_NAME/gamedata/, then re-running. that saves"
    ui_status_info "     the 30 min – 2 h extraction step."
    ui_status_info ""
  fi
}

# ---------------------------------------------------------------------------

_add_realm_collect_identity
_add_realm_register
_add_realm_gamedata_hint
_add_realm_run_phases
