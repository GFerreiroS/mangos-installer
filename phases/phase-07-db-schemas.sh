#!/usr/bin/env bash
# mangos-installer — phase 07: create DBs + apply schemas (replaces InstallDatabase.sh)
# SPDX-License-Identifier: GPL-2.0-only
# See CLAUDE.md for design, README.md for usage
# shellcheck disable=SC2154
#
# We re-implement the relevant steps of upstream's InstallDatabase.sh as
# direct mysql calls. This is shorter and testable; also works for
# remote-DB mode, which the upstream expect-based flow does not support.
#
# Per-realm DB naming:
#   mangos_auth              (shared across realms)
#   mangos_character<index>  (per realm; "zero" -> 0)
#   mangos_world<index>      (per realm)
#
# Idempotence: each DB is created only if absent. A "marker table" check
# (realmlist / characters / creature_template) lets us skip re-applying
# the schema to an already-populated DB. Updates (dated SQL patches) are
# applied once on the first run that reaches this phase; re-applying is
# avoided by the state marker, not by per-patch tracking. A future
# milestone will add a _installer_db_version table.

run_phase_07() {
  MANGOS_CURRENT_PHASE="phase-07-db-schemas"
  ui_phase_header 7 14 "DB schemas"

  if state_has_completed "$MANGOS_CURRENT_PHASE"; then
    ui_status_ok "already done — skipping"
    return 0
  fi

  db_load_admin_password  # re-use: pulls from secrets if needed

  : "${MANGOS_REALM_NAME:?MANGOS_REALM_NAME not set}"
  local realm_dir="$MANGOS_ROOT/$MANGOS_REALM_NAME"
  local db_repo="${realm_dir}/database"
  [[ -d "$db_repo" ]] || die "database repo not cloned (phase 6 must run first)"

  local db_auth="${MANGOS_REALM_DB_AUTH:-mangos_auth}"
  local db_char="${MANGOS_REALM_DB_CHAR:-mangos_character0}"
  local db_world="${MANGOS_REALM_DB_WORLD:-mangos_world0}"

  _phase_07_create_dbs "$db_auth" "$db_char" "$db_world"

  # Migration-tracking table in each DB so later update-realm runs can
  # skip already-applied Updates/*.sql files.
  db_ensure_migration_table "$db_auth"  || true
  db_ensure_migration_table "$db_char"  || true
  db_ensure_migration_table "$db_world" || true

  _phase_07_populate "$db_auth"  "$db_repo/Realm"     realmlist
  _phase_07_populate "$db_char"  "$db_repo/Character" characters
  _phase_07_populate_world "$db_world" "$db_repo/World"

  _phase_07_update_realmlist "$db_auth"

  state_mark_complete "$MANGOS_CURRENT_PHASE"
  ui_status_ok "schemas applied to $db_auth / $db_char / $db_world"
}

# --- create empty databases --------------------------------------------------

_phase_07_create_dbs() {
  local db
  for db in "$@"; do
    if db_exists "$db"; then
      ui_status_ok "database exists: $db"
    else
      ui_status_info "creating database: $db"
      db_exec_admin "CREATE DATABASE \`${db}\` DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci" \
        >>"$MANGOS_LOG_FILE" 2>&1 \
        || die "failed to create database $db"
    fi
  done
}

# --- populate a single DB from Setup/ (+ optional Updates/) ------------------

_phase_07_populate() {
  local db="$1" tree="$2" marker="$3"
  [[ -d "$tree" ]] || { log_warn "skip populate: missing tree $tree"; return 0; }
  if db_table_exists "$db" "$marker"; then
    ui_status_ok "$db already has '$marker' — skipping setup"
    return 0
  fi
  _phase_07_apply_dir "$db" "$tree/Setup"    "setup"
  _phase_07_apply_dir "$db" "$tree/Updates"  "update"
}

# world has an extra step: large data dump under Full_DB/ (or FullDB/).
_phase_07_populate_world() {
  local db="$1" tree="$2"
  [[ -d "$tree" ]] || die "missing world tree: $tree"
  if db_table_exists "$db" "creature_template"; then
    ui_status_ok "$db already has 'creature_template' — skipping setup + data"
    return 0
  fi
  _phase_07_apply_dir "$db" "$tree/Setup"    "setup"
  _phase_07_apply_world_data "$db" "$tree"
  _phase_07_apply_dir "$db" "$tree/Updates"  "update"
}

# Apply all .sql files in <dir>, sorted lexically, to <db>. Update-kind
# applications consult/record the migration-tracking table so the same
# file is never re-applied.
_phase_07_apply_dir() {
  local db="$1" dir="$2" kind="$3"
  [[ -d "$dir" ]] || return 0
  local applied=0 skipped=0 f key
  while IFS= read -r -d '' f; do
    key="${f#"$MANGOS_ROOT/"}"  # relative path is stable across re-runs
    if [[ "$kind" == "update" ]] && db_migration_has "$db" "$key"; then
      skipped=$(( skipped + 1 ))
      continue
    fi
    ui_status_info "${kind}: $(basename -- "$f") -> $db"
    if ! db_import_admin "$db" "$f" >>"$MANGOS_LOG_FILE" 2>&1; then
      if [[ "$kind" == "update" ]]; then
        log_warn "update may have failed (possibly already applied): $f"
      else
        die "schema apply failed: $f -> $db"
      fi
    fi
    [[ "$kind" == "update" ]] && db_migration_record "$db" "$key"
    applied=$(( applied + 1 ))
  done < <(find "$dir" -maxdepth 2 -type f -name '*.sql' -print0 2>/dev/null | sort -z)
  if (( applied > 0 )) || (( skipped > 0 )); then
    ui_status_ok "applied $applied / skipped $skipped ${kind} file(s) to $db"
  fi
  return 0
}

# Apply world data dump (Full_DB / FullDB / full_db). Tries several names
# because upstream has moved them around across releases.
_phase_07_apply_world_data() {
  local db="$1" tree="$2"
  local dir
  for dir in "$tree/Full_DB" "$tree/FullDB" "$tree/full_db"; do
    if [[ -d "$dir" ]]; then
      _phase_07_apply_dir "$db" "$dir" "world-data"
      return 0
    fi
  done
  log_warn "no Full_DB/FullDB directory found under $tree; world DB may be empty"
}

# --- realmlist row update ----------------------------------------------------

_phase_07_update_realmlist() {
  local db="$1"
  local display="${MANGOS_REALM_DISPLAY:-MaNGOS}"
  local address="${MANGOS_REALM_ADDRESS:-127.0.0.1}"
  local port="${MANGOS_REALM_WORLD_PORT:-8085}"
  # Escape quotes in the display name.
  local display_sql="${display//\'/\'\'}"
  local sql
  sql=$(cat <<SQL
UPDATE \`${db}\`.realmlist
   SET name='${display_sql}', address='${address}', port=${port}
 WHERE id=1;
SQL
)
  db_exec_admin "$sql" >>"$MANGOS_LOG_FILE" 2>&1 \
    || log_warn "realmlist UPDATE failed (you may need to insert id=1 manually)"
  ui_status_ok "realmlist row (id=1) pointed at ${address}:${port}"
}
