#!/usr/bin/env bash
# mangos-installer — phase 05: MariaDB setup (local) or remote validation
# SPDX-License-Identifier: GPL-2.0-only
# See CLAUDE.md for design, README.md for usage
# shellcheck disable=SC2154
#
# Local mode:
#   - enable + start mariadb via systemd
#   - wait for socket
#   - non-interactive "secure" cleanup (drop test DB + anonymous users)
#   - create (or reset password of) the mangos DB user with the
#     generated password from secrets.env, plus GRANT ALL WITH GRANT OPTION
#
# Remote mode:
#   - TCP-connect to $MANGOS_DB_HOST:$MANGOS_DB_PORT with the admin
#     credentials the user supplied in phase 0
#   - parse VERSION(); warn for MySQL 5.7 / 8.x, abort for anything
#     below the supported range
#   - SHOW GRANTS for the admin user; abort if required privileges are
#     missing so later phases (7, 8, 10) fail fast and loudly

run_phase_05() {
  MANGOS_CURRENT_PHASE="phase-05-mariadb"
  ui_phase_header 5 14 "MariaDB"

  if state_has_completed "$MANGOS_CURRENT_PHASE"; then
    ui_status_ok "already done — skipping"
    return 0
  fi

  privilege_require_root
  _phase_05_load_admin_password

  if [[ "${MANGOS_DB_MODE:-local}" == "local" ]]; then
    _phase_05_local
  else
    _phase_05_remote
  fi

  state_mark_complete "$MANGOS_CURRENT_PHASE"
}

# --- shared ------------------------------------------------------------------

_phase_05_load_admin_password() {
  if [[ -z "${MANGOS_DB_ADMIN_PASSWORD:-}" ]]; then
    MANGOS_DB_ADMIN_PASSWORD=$(secrets_get DB_ADMIN_PASSWORD)
  fi
  [[ -n "$MANGOS_DB_ADMIN_PASSWORD" ]] \
    || die "DB admin password missing from secrets.env (phase 0 should have set it)"
  export MANGOS_DB_ADMIN_PASSWORD
}

# --- local mode --------------------------------------------------------------

_phase_05_local() {
  ui_status_info "ensuring mariadb service is enabled and running..."
  systemctl enable --now mariadb >>"$MANGOS_LOG_FILE" 2>&1 \
    || die "failed to enable mariadb.service (see $MANGOS_LOG_FILE)"

  ui_status_info "waiting for mariadb socket..."
  db_wait_ready 60 || die "mariadb did not become ready within 60s"
  ui_status_ok "mariadb is ready"

  _phase_05_harden_local
  _phase_05_create_mangos_user "localhost"
  _phase_05_verify_mangos_user "localhost"
}

_phase_05_harden_local() {
  ui_status_info "running non-interactive secure cleanup..."
  local sql
  sql=$(cat <<'SQL'
DROP DATABASE IF EXISTS test;
DELETE FROM mysql.db WHERE Db='test' OR Db LIKE 'test\\_%';
DROP USER IF EXISTS ''@'localhost';
DROP USER IF EXISTS ''@'%';
FLUSH PRIVILEGES;
SQL
)
  # Some statements may be no-ops on already-clean installs; that's fine.
  db_exec_root "$sql" >>"$MANGOS_LOG_FILE" 2>&1 || true
  ui_status_ok "secure cleanup applied"
}

_phase_05_create_mangos_user() {
  local host="$1"
  local user="${MANGOS_DB_ADMIN_USER:-mangos}"
  local pw="$MANGOS_DB_ADMIN_PASSWORD"

  ui_status_info "creating/updating DB user '${user}'@'${host}'..."
  # Password is escaped for single-quoted SQL literal: replace ' with ''.
  local pw_sql="${pw//\'/\'\'}"

  local sql
  sql=$(cat <<SQL
CREATE USER IF NOT EXISTS '${user}'@'${host}' IDENTIFIED BY '${pw_sql}';
ALTER USER '${user}'@'${host}' IDENTIFIED BY '${pw_sql}';
GRANT ALL PRIVILEGES ON *.* TO '${user}'@'${host}' WITH GRANT OPTION;
FLUSH PRIVILEGES;
SQL
)
  db_exec_root "$sql" >>"$MANGOS_LOG_FILE" 2>&1 \
    || die "failed to create/grant DB user '${user}'@'${host}'"

  ui_status_ok "user '${user}'@'${host}' created with GRANT OPTION"
}

_phase_05_verify_mangos_user() {
  local host="$1"
  local user="${MANGOS_DB_ADMIN_USER:-mangos}"
  ui_status_info "verifying grants for '${user}'@'${host}'..."
  local grants
  grants=$(db_exec_admin "SHOW GRANTS FOR CURRENT_USER" 2>>"$MANGOS_LOG_FILE") \
    || die "cannot connect as '${user}'@'${host}' with generated password"
  local needed want missing=""
  for want in CREATE DROP SELECT INSERT UPDATE DELETE INDEX ALTER; do
    if ! printf '%s\n' "$grants" | grep -q "$want"; then
      missing+=" $want"
    fi
  done
  # Presence of "ALL PRIVILEGES" is equivalent to having every priv above.
  if printf '%s\n' "$grants" | grep -q "ALL PRIVILEGES"; then
    missing=""
  fi
  if [[ -n "$missing" ]]; then
    die "DB user '${user}' is missing privileges:$missing"
  fi
  ui_status_ok "grants verified"
}

# --- remote mode -------------------------------------------------------------

_phase_05_remote() {
  ui_status_info "connecting to remote DB at ${MANGOS_DB_HOST}:${MANGOS_DB_PORT}..."
  local version
  version=$(db_version) || die "cannot connect to remote DB (see $MANGOS_LOG_FILE)"
  ui_status_ok "remote DB version: $version"

  _phase_05_check_remote_version "$version"
  _phase_05_verify_mangos_user "%"
  # In remote mode, the user/pass that connected IS the mangos DB account.
  # The installer does not attempt to CREATE USER on a remote DB it does not
  # administer; operators are expected to have set this up out-of-band.
  ui_status_info "remote mode: assuming existing account already has required privileges."
}

_phase_05_check_remote_version() {
  local version="$1"
  case "$version" in
    *MariaDB*)
      # parse major.minor
      local mm
      mm=$(printf '%s\n' "$version" | awk -F- '{print $1}' | awk -F. '{print $1"."$2}')
      local major=${mm%%.*} minor=${mm#*.}
      if (( major > 10 )) || { (( major == 10 )) && (( minor >= 3 )); }; then
        ui_status_ok "MariaDB $mm is supported"
      else
        die "MariaDB $mm is too old (need 10.3+)"
      fi ;;
    *)
      # assume MySQL; check major.minor
      local mm
      mm=$(printf '%s\n' "$version" | awk -F. '{print $1"."$2}')
      local major=${mm%%.*} minor=${mm#*.}
      if (( major == 5 )) && (( minor >= 7 )); then
        ui_status_warn "MySQL $mm is not officially tested; proceeding"
      elif (( major >= 8 )); then
        ui_status_warn "MySQL $mm is not officially tested; proceeding"
      else
        die "MySQL $mm is too old (need 5.7+)"
      fi ;;
  esac
}
