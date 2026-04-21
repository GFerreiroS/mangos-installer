#!/usr/bin/env bash
# mangos-installer — phase 10: generate runtime configs from .conf.dist templates
# SPDX-License-Identifier: GPL-2.0-only
# See CLAUDE.md for design, README.md for usage
# shellcheck disable=SC2154
#
# Copies every <realm>/build/install/etc/*.conf.dist into <realm>/etc/
# (without the .dist suffix) and sed-injects the values this installer
# knows about: DB connection strings, data/log paths, world port, and
# Warden.Enabled=0 (OpenSSL-sidecar compat). ahbot.conf and
# aiplayerbot.conf are copied as-is — operator tweaks those manually.
#
# Always regenerates from the dist templates so configs match the
# current config.env / secrets.env. If an operator has edited a runtime
# .conf file in place, re-running this phase will overwrite it.
#
# Password note: the connection-string format is semicolon-delimited, so
# passwords must not contain ';'. Phase 0's generated passwords are
# alphanumeric only; operators supplying remote-DB passwords should avoid
# ';' in them.

run_phase_10() {
  MANGOS_CURRENT_PHASE="phase-10-configs"
  ui_phase_header 10 14 "configs"

  if state_has_completed "$MANGOS_CURRENT_PHASE"; then
    ui_status_ok "already done — skipping"
    return 0
  fi

  mangos_user_exists || die "mangos user missing (phase 1 must run first)"
  db_load_admin_password  # ensure MANGOS_DB_ADMIN_PASSWORD populated

  : "${MANGOS_REALM_NAME:?MANGOS_REALM_NAME not set}"
  local realm_dir="$MANGOS_ROOT/$MANGOS_REALM_NAME"
  local dist_dir="${realm_dir}/build/install/etc"
  local etc_dir="${realm_dir}/etc"

  [[ -d "$dist_dir" ]] || die "no dist config dir at $dist_dir (phase 8 must run first)"

  _phase_10_copy_all "$dist_dir" "$etc_dir"

  [[ -f "$etc_dir/mangosd.conf" ]] && _phase_10_write_mangosd "$etc_dir/mangosd.conf" "$realm_dir"
  [[ -f "$etc_dir/realmd.conf"  ]] && _phase_10_write_realmd  "$etc_dir/realmd.conf"  "$realm_dir"

  # Perms: 0640 so the mangos user reads and nobody else does (passwords).
  chmod 0640 -- "$etc_dir"/*.conf 2>/dev/null || true
  chown "$MANGOS_USER:$MANGOS_USER" -- "$etc_dir"/*.conf 2>/dev/null || true

  ui_status_ok "configs written to $etc_dir"
  state_mark_complete "$MANGOS_CURRENT_PHASE"
}

# Copy each *.conf.dist to *.conf (drop the .dist suffix). Idempotent.
_phase_10_copy_all() {
  local dist="$1" etc="$2"
  local copied=0 src base dest
  for src in "$dist"/*.conf.dist; do
    [[ -f "$src" ]] || continue
    base=$(basename -- "$src")
    dest="$etc/${base%.dist}"
    cp -f -- "$src" "$dest"
    copied=$(( copied + 1 ))
  done
  ui_status_ok "copied $copied dist template(s)"
}

# Replace the first "^Key = ..." line with the provided value. The value is
# wrapped in double quotes (the mangos config convention). If the key is
# missing the assignment is appended so the line always ends up present.
_phase_10_set_conf_string() {
  local file="$1" key="$2" value="$3"
  local escaped
  # escape & | and \ for sed RHS
  escaped=$(printf '%s' "$value" | sed -e 's/[\\&|]/\\&/g')
  if grep -qE "^${key}[[:space:]]*=" "$file"; then
    sed -i -E "s|^${key}[[:space:]]*=.*|${key} = \"${escaped}\"|" "$file"
  else
    printf '%s = "%s"\n' "$key" "$value" >> "$file"
  fi
}

_phase_10_set_conf_number() {
  local file="$1" key="$2" value="$3"
  if grep -qE "^${key}[[:space:]]*=" "$file"; then
    sed -i -E "s|^${key}[[:space:]]*=.*|${key} = ${value}|" "$file"
  else
    printf '%s = %s\n' "$key" "$value" >> "$file"
  fi
}

# --- mangosd.conf ------------------------------------------------------------

_phase_10_write_mangosd() {
  local conf="$1" realm_dir="$2"
  local host="${MANGOS_DB_HOST:-localhost}"
  local port="${MANGOS_DB_PORT:-3306}"
  local user="${MANGOS_DB_ADMIN_USER:-mangos}"
  local pw="$MANGOS_DB_ADMIN_PASSWORD"
  local db_auth="${MANGOS_REALM_DB_AUTH:-mangos_auth}"
  local db_char="${MANGOS_REALM_DB_CHAR:-mangos_character0}"
  local db_world="${MANGOS_REALM_DB_WORLD:-mangos_world0}"

  _phase_10_set_conf_string "$conf" LoginDatabaseInfo     "$host;$port;$user;$pw;$db_auth"
  _phase_10_set_conf_string "$conf" WorldDatabaseInfo     "$host;$port;$user;$pw;$db_world"
  _phase_10_set_conf_string "$conf" CharacterDatabaseInfo "$host;$port;$user;$pw;$db_char"
  _phase_10_set_conf_string "$conf" DataDir               "${realm_dir}/gamedata"
  _phase_10_set_conf_string "$conf" LogsDir               "${realm_dir}/logs"
  _phase_10_set_conf_number "$conf" WorldServerPort       "${MANGOS_REALM_WORLD_PORT:-8085}"
  _phase_10_set_conf_number "$conf" Warden.Enabled        "0"

  ui_status_ok "mangosd.conf written"
}

# --- realmd.conf -------------------------------------------------------------

_phase_10_write_realmd() {
  local conf="$1" realm_dir="$2"
  local host="${MANGOS_DB_HOST:-localhost}"
  local port="${MANGOS_DB_PORT:-3306}"
  local user="${MANGOS_DB_ADMIN_USER:-mangos}"
  local pw="$MANGOS_DB_ADMIN_PASSWORD"
  local db_auth="${MANGOS_REALM_DB_AUTH:-mangos_auth}"

  _phase_10_set_conf_string "$conf" LoginDatabaseInfo "$host;$port;$user;$pw;$db_auth"
  _phase_10_set_conf_number "$conf" RealmServerPort   "3724"
  _phase_10_set_conf_string "$conf" LogsDir           "${realm_dir}/logs"

  ui_status_ok "realmd.conf written"
}
