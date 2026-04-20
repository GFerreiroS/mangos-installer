#!/usr/bin/env bash
# mangos-installer — rebuild an existing realm at a newer upstream ref
# SPDX-License-Identifier: GPL-2.0-only
# See CLAUDE.md for design, README.md for usage
# shellcheck shell=bash disable=SC2154
#
# 1. pick realm, resolve latest upstream ref
# 2. mysqldump -> <realm>/backups/pre-update-<ts>.sql.gz for all 3 DBs
# 3. tag the source checkout "installer-pre-update-<ts>" for rollback
# 4. systemctl stop mangos-mangosd@<realm>
# 5. re-run phases 6 (new ref) and 8/9/10 against the updated tree
# 6. re-apply database/Updates/*.sql against world + character DBs
#    (naive re-apply; the update files are idempotent most of the time,
#    and SQL errors are captured in the log for operator review)
# 7. systemctl start mangos-mangosd@<realm>; run phase 14 smoke
# 8. on failure at any point, roll back to the pre-update git tag and
#    restore the DB dumps, then restart services. Clear message about
#    what happened and where the backups / tag live.

ui_print_banner "mangos installer ${INSTALLER_VERSION} — update a realm"

config_load

UPDATE_REALM=""
UPDATE_OLD_REF=""
UPDATE_NEW_REF=""
UPDATE_TS=""
UPDATE_BACKUP_DIR=""
UPDATE_GIT_TAG=""
UPDATE_PRE_BACKUPS_DONE=0
UPDATE_STOPPED_WORLD=0

_update_pick_realm() {
  local realms r count=0
  realms=$(state_list_realms)
  [[ -z "$realms" ]] && die "no realms found in config.env"
  mapfile -t _realms < <(printf '%s\n' "$realms")
  if [[ "${#_realms[@]}" -eq 1 ]]; then
    UPDATE_REALM="${_realms[0]}"
    ui_status_info "updating realm: $UPDATE_REALM"
    return 0
  fi
  ui_status_info "installed realms:"
  for r in "${_realms[@]}"; do
    ui_status_info "  $r"
  done
  UPDATE_REALM=$(ui_prompt_text "which realm to update?" "${_realms[0]}" "MANGOS_UPDATE_REALM")
  printf '%s\n' "${_realms[@]}" | grep -qx -- "$UPDATE_REALM" \
    || die "unknown realm '$UPDATE_REALM'"
  ui_status_info "updating realm: $UPDATE_REALM"
}

_update_resolve_ref() {
  local api_json
  UPDATE_OLD_REF=$(config_get "REALM_${UPDATE_REALM}_MANGOS_REF")
  if api_json=$(curl -fsSL --max-time 15 "$MANGOS_ZERO_RELEASES_API" 2>>"$MANGOS_LOG_FILE"); then
    UPDATE_NEW_REF=$(printf '%s\n' "$api_json" \
      | sed -nE 's/.*"tag_name": *"([^"]+)".*/\1/p' | head -n 1)
  fi
  [[ -z "$UPDATE_NEW_REF" ]] && UPDATE_NEW_REF="$MANGOS_FALLBACK_REF"

  ui_status_info "current ref: ${UPDATE_OLD_REF:-unknown}"
  ui_status_info "latest ref:  $UPDATE_NEW_REF"

  if [[ "$UPDATE_OLD_REF" == "$UPDATE_NEW_REF" ]]; then
    ui_status_info "already on latest."
    if ! ui_prompt_yes_no "force rebuild anyway?" "no" "MANGOS_UPDATE_FORCE"; then
      ui_status_ok "nothing to do."
      exit 0
    fi
  else
    if ! ui_prompt_yes_no "update ${UPDATE_OLD_REF:-?} -> ${UPDATE_NEW_REF}?" "yes" "MANGOS_UPDATE_CONFIRM"; then
      ui_status_info "aborted by operator."
      exit 0
    fi
  fi
}

_update_backup_dbs() {
  UPDATE_TS=$(date -u +'%Y%m%d-%H%M%S')
  UPDATE_BACKUP_DIR="$MANGOS_ROOT/$UPDATE_REALM/backups"
  install -d -m 0755 -o "$MANGOS_USER" -g "$MANGOS_USER" -- "$UPDATE_BACKUP_DIR"
  local db kind
  _phase_05_load_admin_password
  for kind in DB_AUTH DB_CHAR DB_WORLD; do
    db=$(config_get "REALM_${UPDATE_REALM}_${kind}")
    [[ -z "$db" ]] && continue
    local out="$UPDATE_BACKUP_DIR/pre-update-${UPDATE_TS}-${db}.sql.gz"
    ui_status_info "dumping $db -> $(basename -- "$out")"
    if ! db_dump_database "$db" "$out" 2>>"$MANGOS_LOG_FILE"; then
      die "mysqldump of $db failed; aborting update before any changes"
    fi
    chown "$MANGOS_USER:$MANGOS_USER" -- "$out" 2>/dev/null || true
  done
  UPDATE_PRE_BACKUPS_DONE=1
  ui_status_ok "DB dumps in $UPDATE_BACKUP_DIR"
}

_update_tag_source() {
  UPDATE_GIT_TAG="installer-pre-update-${UPDATE_TS}"
  local src="$MANGOS_ROOT/$UPDATE_REALM/source"
  [[ -d "$src/.git" ]] || { log_warn "no .git at $src; skipping rollback tag"; return 0; }
  local script
  script=$(mktemp --tmpdir "mi-tag.XXXXXX.sh")
  cat > "$script" <<TAG
#!/usr/bin/env bash
set -euo pipefail
cd "$src"
git tag -f "$UPDATE_GIT_TAG" HEAD
TAG
  chmod 0755 -- "$script"
  run_script_as_mangos "$script" >>"$MANGOS_LOG_FILE" 2>&1 \
    || log_warn "could not tag source for rollback (continuing)"
  rm -f -- "$script"
  ui_status_ok "source tagged $UPDATE_GIT_TAG for rollback"
}

_update_stop_world() {
  systemd_have || { log_warn "no systemd; cannot stop mangosd@${UPDATE_REALM}"; return 0; }
  ui_status_info "stopping mangos-mangosd@${UPDATE_REALM}..."
  systemd_stop "mangos-mangosd@${UPDATE_REALM}.service"
  UPDATE_STOPPED_WORLD=1
}

_update_rebuild() {
  # Set up the runner's "this realm is current" state as if the first
  # fresh install had just done phase 0. The per-realm phases already
  # read MANGOS_REALM_* from the hydrated env.
  config_hydrate_realm "$UPDATE_REALM"
  state_switch_to_realm "$UPDATE_REALM"

  # Force a fresh run of 6, 8, 9, 10 by clearing their markers.
  state_reset "phase-06-fetch-sources"
  state_reset "phase-08-build"
  state_reset "phase-09-install-binaries"
  state_reset "phase-10-configs"

  # Override the ref the phase-6 resolver would pick. phase-6 calls the
  # API itself; we short-circuit by exporting the pinned ref into a
  # dedicated env var that a small wrapper function reads. Easier: set
  # the REALM config key so phase 6 records the right value and make
  # phase 6 trust MANGOS_FORCE_REF when set.
  export MANGOS_FORCE_REF="$UPDATE_NEW_REF"

  local p num fn
  for p in phase-06-fetch-sources phase-08-build phase-09-install-binaries phase-10-configs; do
    # shellcheck disable=SC1090
    . "$MANGOS_INSTALLER_DIR/phases/${p}.sh"
    num="${p#phase-}"
    num="${num%%-*}"
    fn="run_phase_${num}"
    "$fn"
    state_json_write || true
  done
}

_update_apply_db_updates() {
  local db_repo="$MANGOS_ROOT/$UPDATE_REALM/database"
  local char_db world_db
  char_db=$(config_get "REALM_${UPDATE_REALM}_DB_CHAR")
  world_db=$(config_get "REALM_${UPDATE_REALM}_DB_WORLD")
  ui_status_info "re-applying database/Updates/*.sql (errors logged, not fatal)..."
  _phase_05_load_admin_password
  local f applied=0
  shopt -s nullglob
  for f in "$db_repo/Character/Updates"/*.sql "$db_repo/Character/Updates"/*/*.sql; do
    [[ -f "$f" ]] && { db_import_admin "$char_db" "$f" >>"$MANGOS_LOG_FILE" 2>&1 || true; applied=$(( applied + 1 )); }
  done
  for f in "$db_repo/World/Updates"/*.sql "$db_repo/World/Updates"/*/*.sql; do
    [[ -f "$f" ]] && { db_import_admin "$world_db" "$f" >>"$MANGOS_LOG_FILE" 2>&1 || true; applied=$(( applied + 1 )); }
  done
  shopt -u nullglob
  ui_status_ok "attempted to apply $applied update file(s); see log for per-file errors"
  ui_status_warn "schema-breaking upstream changes are NOT auto-migrated;"
  ui_status_warn "review upstream release notes for ${UPDATE_OLD_REF:-?} -> ${UPDATE_NEW_REF}."
}

_update_start_and_smoke() {
  systemd_have || { log_warn "no systemd; skipping start+smoke"; return 0; }
  ui_status_info "starting mangos-mangosd@${UPDATE_REALM}..."
  systemd_start "mangos-mangosd@${UPDATE_REALM}.service" \
    || die "mangos-mangosd@${UPDATE_REALM} failed to restart after update (see journalctl)"
  state_reset "phase-14-smoke"
  # shellcheck disable=SC1090
  . "$MANGOS_INSTALLER_DIR/phases/phase-14-smoke.sh"
  run_phase_14
}

_update_rollback() {
  ui_print_banner "update FAILED — rolling back realm '$UPDATE_REALM'"
  local src="$MANGOS_ROOT/$UPDATE_REALM/source"

  if [[ -n "$UPDATE_GIT_TAG" ]] && [[ -d "$src/.git" ]]; then
    ui_status_info "resetting source to $UPDATE_GIT_TAG..."
    local script
    script=$(mktemp --tmpdir "mi-rollback.XXXXXX.sh")
    cat > "$script" <<ROLL
#!/usr/bin/env bash
set -euo pipefail
cd "$src"
git reset --hard "$UPDATE_GIT_TAG"
git submodule update --init --recursive
ROLL
    chmod 0755 -- "$script"
    run_script_as_mangos "$script" >>"$MANGOS_LOG_FILE" 2>&1 || true
    rm -f -- "$script"
  fi

  if (( UPDATE_PRE_BACKUPS_DONE )); then
    ui_status_info "restoring DB dumps from $UPDATE_BACKUP_DIR..."
    _phase_05_load_admin_password
    local kind db dump
    for kind in DB_AUTH DB_CHAR DB_WORLD; do
      db=$(config_get "REALM_${UPDATE_REALM}_${kind}")
      dump="$UPDATE_BACKUP_DIR/pre-update-${UPDATE_TS}-${db}.sql.gz"
      [[ -f "$dump" ]] || continue
      db_exec_admin "DROP DATABASE IF EXISTS \`$db\`; CREATE DATABASE \`$db\`" \
        >>"$MANGOS_LOG_FILE" 2>&1 || true
      gunzip -c "$dump" | MYSQL_PWD="${MANGOS_DB_ADMIN_PASSWORD:-}" \
        "$(db_client)" -h "${MANGOS_DB_HOST:-localhost}" -P "${MANGOS_DB_PORT:-3306}" \
                       -u "${MANGOS_DB_ADMIN_USER:-mangos}" "$db" \
        >>"$MANGOS_LOG_FILE" 2>&1 || log_warn "restore failed for $db"
    done
  fi

  if (( UPDATE_STOPPED_WORLD )) && systemd_have; then
    systemd_start "mangos-mangosd@${UPDATE_REALM}.service" >>"$MANGOS_LOG_FILE" 2>&1 || true
  fi

  ui_status_fail "rollback complete. source tag: ${UPDATE_GIT_TAG:-<none>}"
  ui_status_info "db backups remain at: $UPDATE_BACKUP_DIR"
  ui_status_info "installer log:        $MANGOS_LOG_FILE"
}

_update_main() {
  _update_pick_realm
  _update_resolve_ref
  _update_backup_dbs
  _update_tag_source
  _update_stop_world
  _update_rebuild
  _update_apply_db_updates
  _update_start_and_smoke

  config_set "REALM_${UPDATE_REALM}_MANGOS_REF"   "$UPDATE_NEW_REF"
  config_set "REALM_${UPDATE_REALM}_LAST_UPDATED" "$(date -u +'%Y-%m-%dT%H:%M:%SZ')"
  config_set "REALM_${UPDATE_REALM}_STATUS"       "installed"
  state_json_write || true

  ui_print_banner "update complete: ${UPDATE_OLD_REF:-?} -> ${UPDATE_NEW_REF}"
  ui_status_info "db backups: $UPDATE_BACKUP_DIR"
  ui_status_info "rollback:   git -C <source> reset --hard $UPDATE_GIT_TAG (still valid)"
}

# Trap any non-zero exit during the update to run the rollback path.
trap '_update_rollback' ERR
set -E
_update_main
trap - ERR
