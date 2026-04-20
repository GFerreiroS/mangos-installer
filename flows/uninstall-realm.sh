#!/usr/bin/env bash
# mangos-installer — remove a single realm (DB, services, files); keep backups
# SPDX-License-Identifier: GPL-2.0-only
# See CLAUDE.md for design, README.md for usage
# shellcheck shell=bash disable=SC2154
#
# 1. pick realm; type-confirm by typing the realm name exactly
# 2. mysqldump a final safety backup -> <realm>/backups/final-<ts>.sql.gz
# 3. stop + disable mangos-mangosd@<realm>; if this was the last realm,
#    also stop + disable mangos-realmd
# 4. DROP the character and world DBs; keep mangos_auth unless this is
#    the last realm (DROP it then too)
# 5. rm -rf <realm_dir>/{source,database,build,bin,etc,gamedata,logs}
#    — preserve <realm_dir>/backups
# 6. update config.env: REALM_<name>_STATUS=uninstalled (do NOT remove the
#    block; keeping history helps with diagnostics)

ui_print_banner "mangos installer ${INSTALLER_VERSION} — uninstall a realm"

config_load

_uninstall_realm_pick() {
  local realms
  realms=$(state_list_realms)
  [[ -z "$realms" ]] && die "no realms found in config.env"
  mapfile -t _realms < <(printf '%s\n' "$realms")

  ui_status_info "installed realms:"
  local r
  for r in "${_realms[@]}"; do ui_status_info "  $r"; done

  REALM=$(ui_prompt_text "which realm to uninstall?" "${_realms[0]}" "MANGOS_UNINSTALL_REALM")
  printf '%s\n' "${_realms[@]}" | grep -qx -- "$REALM" \
    || die "unknown realm '$REALM'"

  # Typed confirmation to prevent accidents.
  if [[ "${MANGOS_CONFIRM_UNINSTALL:-}" != "yes" ]]; then
    local typed
    while :; do
      read -rp "type the realm name '$REALM' to confirm: " typed
      [[ "$typed" == "$REALM" ]] && break
      ui_status_warn "doesn't match. try again or Ctrl-C to abort."
    done
  fi
}

_uninstall_realm_final_backup() {
  local ts
  ts=$(date -u +'%Y%m%d-%H%M%S')
  local bdir="$MANGOS_ROOT/$REALM/backups"
  install -d -m 0755 -o "$MANGOS_USER" -g "$MANGOS_USER" -- "$bdir"
  _phase_05_load_admin_password || true
  local kind db out
  for kind in DB_AUTH DB_CHAR DB_WORLD; do
    db=$(config_get "REALM_${REALM}_${kind}")
    [[ -z "$db" ]] && continue
    # Skip auth DB when other realms still use it (we'd just re-dump on each).
    if [[ "$kind" == "DB_AUTH" ]] && (( $(state_list_realms | grep -cv "^${REALM}$") > 0 )); then
      continue
    fi
    out="$bdir/final-${ts}-${db}.sql.gz"
    ui_status_info "final backup: $db -> $(basename -- "$out")"
    db_dump_database "$db" "$out" 2>>"$MANGOS_LOG_FILE" || log_warn "final backup of $db failed"
  done
  ui_status_ok "final backups preserved in $bdir"
  FINAL_TS="$ts"
}

_uninstall_realm_stop_services() {
  if systemd_have; then
    ui_status_info "stopping + disabling mangos-mangosd@${REALM}..."
    systemd_stop    "mangos-mangosd@${REALM}.service"
    systemd_disable "mangos-mangosd@${REALM}.service"

    # If this was the last realm, also stop realmd.
    local others
    others=$(state_list_realms | grep -vx -- "$REALM" || true)
    if [[ -z "$others" ]]; then
      ui_status_info "last realm — also stopping + disabling mangos-realmd..."
      systemd_stop    "mangos-realmd.service"
      systemd_disable "mangos-realmd.service"
    fi
  else
    log_warn "no systemd; skipping service stop"
  fi
}

_uninstall_realm_drop_dbs() {
  _phase_05_load_admin_password || true
  local db_char db_world db_auth
  db_char=$(config_get "REALM_${REALM}_DB_CHAR")
  db_world=$(config_get "REALM_${REALM}_DB_WORLD")
  db_auth=$(config_get "REALM_${REALM}_DB_AUTH")

  [[ -n "$db_char"  ]] && { ui_status_info "DROP $db_char";  db_drop_database "$db_char"  || log_warn "drop $db_char failed"; }
  [[ -n "$db_world" ]] && { ui_status_info "DROP $db_world"; db_drop_database "$db_world" || log_warn "drop $db_world failed"; }

  # Drop auth only when no other realm still points at it (usually: last realm).
  local others_using=0 other
  while IFS= read -r other; do
    [[ -z "$other" ]] && continue
    [[ "$other" == "$REALM" ]] && continue
    local a
    a=$(config_get "REALM_${other}_DB_AUTH")
    [[ "$a" == "$db_auth" ]] && others_using=$(( others_using + 1 ))
  done < <(state_list_realms)
  if (( others_using == 0 )) && [[ -n "$db_auth" ]]; then
    ui_status_info "DROP $db_auth (last realm — no other realm references it)"
    db_drop_database "$db_auth" || log_warn "drop $db_auth failed"
  fi
}

_uninstall_realm_remove_files() {
  local realm_dir="$MANGOS_ROOT/$REALM"
  [[ -d "$realm_dir" ]] || return 0
  # Preserve backups/.
  local sub
  for sub in source database build bin etc gamedata logs; do
    [[ -e "$realm_dir/$sub" ]] && rm -rf -- "$realm_dir/$sub"
  done
  # Drop any stray files at the root of the realm dir (keep backups/).
  find "$realm_dir" -mindepth 1 -maxdepth 1 ! -name backups -print -exec rm -rf -- {} + \
    >>"$MANGOS_LOG_FILE" 2>&1 || true
  ui_status_ok "removed $realm_dir (backups preserved at $realm_dir/backups)"
}

_uninstall_realm_update_config() {
  config_set "REALM_${REALM}_STATUS"          "uninstalled"
  config_set "REALM_${REALM}_UNINSTALLED_AT"  "$(date -u +'%Y-%m-%dT%H:%M:%SZ')"
  local current
  current=$(config_get MANGOS_CURRENT_REALM)
  if [[ "$current" == "$REALM" ]]; then
    # Pick another realm (if any) as the current pointer.
    local pick
    pick=$(state_list_realms | grep -vx -- "$REALM" | head -n 1 || true)
    config_set MANGOS_CURRENT_REALM "${pick:-}"
  fi
  state_json_write || true
}

# ---------------------------------------------------------------------------

REALM=""
FINAL_TS=""

_uninstall_realm_pick
_uninstall_realm_final_backup
_uninstall_realm_stop_services
_uninstall_realm_drop_dbs
_uninstall_realm_remove_files
_uninstall_realm_update_config

ui_print_banner "realm '$REALM' uninstalled"
ui_status_info "backups preserved at: $MANGOS_ROOT/$REALM/backups/"
ui_status_info "installer log:        $MANGOS_LOG_FILE"
