#!/usr/bin/env bash
# mangos-installer — phase 02: install apt build / runtime dependencies
# SPDX-License-Identifier: GPL-2.0-only
# See CLAUDE.md for design, README.md for usage
# shellcheck disable=SC2154
#
# One apt-get install with the full dependency list. Runs non-interactively
# (DEBIAN_FRONTEND=noninteractive). mariadb-server is conditional on
# DB_MODE=local. unrar / p7zip-full are NOT installed here; archive.sh
# installs them on demand when gamedata extraction actually needs them
# (keeps the default dependency surface smaller).
#
# Community fixes baked in:
#   - libreadline-dev (Cr10)
#   - liblua5.2-dev    (silentlabber)
#   - default-libmysqlclient-dev (provides both MariaDB and MySQL headers)

run_phase_02() {
  MANGOS_CURRENT_PHASE="phase-02-apt-deps"
  ui_phase_header 2 14 "apt dependencies"

  if state_has_completed "$MANGOS_CURRENT_PHASE"; then
    ui_status_ok "already done — skipping"
    return 0
  fi

  privilege_require_root

  local -a packages=(
    git make cmake build-essential
    libssl-dev libbz2-dev
    default-libmysqlclient-dev
    libace-dev libreadline-dev liblua5.2-dev
    python3 net-tools gdb
    zip unzip wget curl ca-certificates
  )

  # mariadb-client always; mariadb-server only in local mode.
  packages+=( mariadb-client )
  if [[ "${MANGOS_DB_MODE:-local}" == "local" ]]; then
    packages+=( mariadb-server )
  fi

  ui_status_info "apt-get update..."
  DEBIAN_FRONTEND=noninteractive apt-get update -qq >>"$MANGOS_LOG_FILE" 2>&1 \
    || die "apt-get update failed (see $MANGOS_LOG_FILE)"

  ui_status_info "apt-get install (${#packages[@]} packages)..."
  DEBIAN_FRONTEND=noninteractive apt-get install -y -qq --no-install-recommends \
    -o Dpkg::Options::=--force-confdef \
    -o Dpkg::Options::=--force-confold \
    -- "${packages[@]}" >>"$MANGOS_LOG_FILE" 2>&1 \
    || die "apt-get install failed (see $MANGOS_LOG_FILE)"

  ui_status_ok "installed: ${packages[*]}"
  state_mark_complete "$MANGOS_CURRENT_PHASE"
}
