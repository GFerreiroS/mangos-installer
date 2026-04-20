#!/usr/bin/env bash
# mangos-installer — phase 13: install systemd units, daemon-reload, enable
# SPDX-License-Identifier: GPL-2.0-only
# See CLAUDE.md for design, README.md for usage
# shellcheck disable=SC2154
#
# Does NOT start services (that is phase 14). Enable is idempotent;
# daemon-reload only runs when a unit file actually changed.

run_phase_13() {
  MANGOS_CURRENT_PHASE="phase-13-systemd"
  ui_phase_header 13 14 "systemd"

  if state_has_completed "$MANGOS_CURRENT_PHASE"; then
    ui_status_ok "already done — skipping"
    return 0
  fi

  privilege_require_root
  : "${MANGOS_REALM_NAME:?MANGOS_REALM_NAME not set}"

  if ! systemd_have; then
    die "systemd is not available on this host — cannot install units"
  fi

  systemd_install_units || die "failed to install systemd unit files"
  ui_status_ok "units installed under $SYSTEMD_UNIT_DIR"

  systemd_enable "mangos-realmd.service" \
    || die "failed to enable mangos-realmd.service"
  systemd_enable "mangos-mangosd@${MANGOS_REALM_NAME}.service" \
    || die "failed to enable mangos-mangosd@${MANGOS_REALM_NAME}.service"

  ui_status_ok "enabled: mangos-realmd"
  ui_status_ok "enabled: mangos-mangosd@${MANGOS_REALM_NAME}"

  state_mark_complete "$MANGOS_CURRENT_PHASE"
}
