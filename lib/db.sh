#!/usr/bin/env bash
# mangos-installer — MariaDB / MySQL helpers
# SPDX-License-Identifier: GPL-2.0-only
# See CLAUDE.md for design, README.md for usage
# shellcheck shell=bash
#
# Wraps the mariadb / mysql client invocations used by phases 5 and 7.
# Password handling goes through MYSQL_PWD so it never lands in ps / argv.
# The default client binary is `mariadb` (which is also provided as `mysql`
# on Debian/Ubuntu MariaDB packages).

db_client() {
  if command -v mariadb >/dev/null 2>&1; then
    printf 'mariadb\n'
  elif command -v mysql >/dev/null 2>&1; then
    printf 'mysql\n'
  else
    return 1
  fi
}

# db_exec_root <sql> — run a single SQL statement as a privileged admin.
# Local mode: uses the mariadb unix_socket auth as root (via sudo).
# Remote mode: connects with MANGOS_DB_ADMIN_USER / MANGOS_DB_ADMIN_PASSWORD.
db_exec_root() {
  local sql="$1"
  local cli
  cli=$(db_client) || { log_error "no mariadb/mysql client installed"; return 1; }
  if [[ "${MANGOS_DB_MODE:-local}" == "local" ]]; then
    sudo "$cli" --protocol=socket -e "$sql"
  else
    MYSQL_PWD="${MANGOS_DB_ADMIN_PASSWORD:-}" "$cli" \
      -h "${MANGOS_DB_HOST:-localhost}" \
      -P "${MANGOS_DB_PORT:-3306}" \
      -u "${MANGOS_DB_ADMIN_USER:-mangos}" \
      -e "$sql"
  fi
}

# db_exec_admin <sql> — run as the mangos DB admin user (created in phase 5).
# Works in both local and remote mode via MYSQL_PWD + TCP.
db_exec_admin() {
  local sql="$1"
  local cli
  cli=$(db_client) || { log_error "no mariadb/mysql client installed"; return 1; }
  MYSQL_PWD="${MANGOS_DB_ADMIN_PASSWORD:-}" "$cli" \
    -h "${MANGOS_DB_HOST:-localhost}" \
    -P "${MANGOS_DB_PORT:-3306}" \
    -u "${MANGOS_DB_ADMIN_USER:-mangos}" \
    -e "$sql"
}

# db_import_admin <database> <sql-file> — stream a SQL file into <database>.
db_import_admin() {
  local db="$1" file="$2"
  local cli
  cli=$(db_client) || { log_error "no mariadb/mysql client installed"; return 1; }
  [[ -r "$file" ]] || { log_error "db_import_admin: not readable: $file"; return 1; }
  MYSQL_PWD="${MANGOS_DB_ADMIN_PASSWORD:-}" "$cli" \
    -h "${MANGOS_DB_HOST:-localhost}" \
    -P "${MANGOS_DB_PORT:-3306}" \
    -u "${MANGOS_DB_ADMIN_USER:-mangos}" \
    "$db" < "$file"
}

# db_version — print the server version string (e.g. "10.11.8-MariaDB").
db_version() {
  db_exec_admin "SELECT VERSION()" 2>/dev/null | awk 'NR==2 { print $1 }'
}

# db_exists <database>
db_exists() {
  local db="$1"
  local count
  count=$(db_exec_admin "SELECT COUNT(*) FROM information_schema.schemata WHERE schema_name='${db}'" 2>/dev/null \
           | awk 'NR==2 { print $1 }')
  [[ "${count:-0}" -gt 0 ]]
}

# db_table_exists <database> <table>
db_table_exists() {
  local db="$1" table="$2"
  local count
  count=$(db_exec_admin "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema='${db}' AND table_name='${table}'" 2>/dev/null \
           | awk 'NR==2 { print $1 }')
  [[ "${count:-0}" -gt 0 ]]
}

# db_dump_database <database> <output-file.sql.gz>
# Dumps <database> via mysqldump and compresses with gzip. Works in both
# local (socket-auth) and remote (TCP + MYSQL_PWD) modes. Used by the
# update-realm and uninstall flows for pre-op backups.
db_dump_database() {
  local db="$1" out="$2"
  local dumper=""
  if command -v mariadb-dump >/dev/null 2>&1; then
    dumper="mariadb-dump"
  elif command -v mysqldump >/dev/null 2>&1; then
    dumper="mysqldump"
  else
    log_error "no mysqldump/mariadb-dump client installed"
    return 1
  fi
  mkdir -p -- "$(dirname -- "$out")"
  local tmp="${out}.part"
  if [[ "${MANGOS_DB_MODE:-local}" == "local" ]]; then
    sudo "$dumper" --protocol=socket \
      --single-transaction --routines --triggers --events \
      "$db" | gzip > "$tmp"
  else
    MYSQL_PWD="${MANGOS_DB_ADMIN_PASSWORD:-}" "$dumper" \
      -h "${MANGOS_DB_HOST:-localhost}" \
      -P "${MANGOS_DB_PORT:-3306}" \
      -u "${MANGOS_DB_ADMIN_USER:-mangos}" \
      --single-transaction --routines --triggers --events \
      "$db" | gzip > "$tmp"
  fi
  mv -- "$tmp" "$out"
}

# db_drop_database <database> — DROP DATABASE IF EXISTS.
db_drop_database() {
  db_exec_admin "DROP DATABASE IF EXISTS \`$1\`" >/dev/null 2>&1
}

# db_wait_ready [<timeout-seconds>] — poll until the server accepts a
# trivial query or the timeout elapses.
db_wait_ready() {
  local timeout="${1:-30}"
  local cli
  cli=$(db_client) || return 1
  local deadline=$(( $(date +%s) + timeout ))
  while (( $(date +%s) < deadline )); do
    if [[ "${MANGOS_DB_MODE:-local}" == "local" ]]; then
      if sudo "$cli" --protocol=socket -e "SELECT 1" >/dev/null 2>&1; then
        return 0
      fi
    else
      if db_exec_admin "SELECT 1" >/dev/null 2>&1; then
        return 0
      fi
    fi
    sleep 1
  done
  return 1
}
