#!/usr/bin/env bash
# mangos-installer — phase 14: start services, verify ports, print success banner
# SPDX-License-Identifier: GPL-2.0-only
# See CLAUDE.md for design, README.md for usage
# shellcheck disable=SC2154
#
# Starts realmd first, waits for port 3724 to open, then starts the
# per-realm mangosd and waits for the world port. On any failure, pulls
# the last 50 lines of journalctl for the failing unit into the log and
# dies with a pointer to journalctl for full details.

run_phase_14() {
  MANGOS_CURRENT_PHASE="phase-14-smoke"
  ui_phase_header 14 14 "smoke test"

  : "${MANGOS_REALM_NAME:?MANGOS_REALM_NAME not set}"
  local realm="$MANGOS_REALM_NAME"
  local world_port="${MANGOS_REALM_WORLD_PORT:-8085}"
  local auth_unit="mangos-realmd.service"
  local world_unit="mangos-mangosd@${realm}.service"

  if state_has_completed "$MANGOS_CURRENT_PHASE"; then
    if systemd_is_active "$auth_unit" && systemd_is_active "$world_unit"; then
      ui_status_ok "already done — services still active"
      _phase_14_success_banner "$realm" "$world_port"
      return 0
    fi
    ui_status_warn "state says done but services not active; restarting"
    state_reset "$MANGOS_CURRENT_PHASE"
  fi

  privilege_require_root
  systemd_have || die "systemd is not available on this host"

  # --- realmd ---------------------------------------------------------------
  ui_status_info "starting ${auth_unit}..."
  if ! systemd_start "$auth_unit"; then
    systemd_journal_tail "$auth_unit" 50
    die "${auth_unit} failed to start (journalctl -u $auth_unit for details)"
  fi
  if ! systemd_wait_port 3724 15; then
    systemd_journal_tail "$auth_unit" 50
    die "${auth_unit} did not open port 3724 within 15s"
  fi
  ui_status_ok "${auth_unit} active, port 3724 open"

  # --- mangosd --------------------------------------------------------------
  ui_status_info "starting ${world_unit} (world startup may take up to 120s)..."
  if ! systemd_start "$world_unit"; then
    systemd_journal_tail "$world_unit" 50
    die "${world_unit} failed to start (journalctl -u $world_unit for details)"
  fi
  if ! systemd_wait_port "$world_port" 120; then
    systemd_journal_tail "$world_unit" 50
    die "${world_unit} did not open port ${world_port} within 120s"
  fi
  ui_status_ok "${world_unit} active, port ${world_port} open"

  # Final post-check: both units still healthy?
  systemd_is_active "$auth_unit"  || { systemd_journal_tail "$auth_unit"  50; die "${auth_unit} died after start"; }
  systemd_is_active "$world_unit" || { systemd_journal_tail "$world_unit" 50; die "${world_unit} died after start"; }

  config_set "REALM_${realm}_STATUS"          "installed"
  config_set "REALM_${realm}_LAST_UPDATED"    "$(date -u +'%Y-%m-%dT%H:%M:%SZ')"

  state_mark_complete "$MANGOS_CURRENT_PHASE"
  _phase_14_success_banner "$realm" "$world_port"
}

_phase_14_success_banner() {
  local realm="$1" world_port="$2"
  local state_json="$MANGOS_ROOT/.installer/state.json"

  ui_print_banner "install complete — realm '${realm}' is running"
  ui_status_ok "realm:       ${realm}  (display: ${MANGOS_REALM_DISPLAY:-${realm}})"
  ui_status_ok "address:     ${MANGOS_REALM_ADDRESS:-127.0.0.1}:${world_port}"
  ui_status_ok "auth port:   3724  (shared across realms)"
  ui_status_ok "services:    mangos-realmd, mangos-mangosd@${realm}"
  ui_status_info ""
  ui_status_info "start/stop/monitor:"
  ui_status_info "  sudo systemctl status mangos-realmd mangos-mangosd@${realm}"
  ui_status_info "  sudo journalctl -fu mangos-mangosd@${realm}"
  ui_status_info ""
  ui_status_warn "DEFAULT ACCOUNTS ARE ACTIVE — change them before exposing to the internet."
  ui_status_warn "the mangos schema creates ADMINISTRATOR/ADMINISTRATOR and similar."
  ui_status_warn "log in with your WoW 1.12.x client, then use GM commands (\`.account set\`)"
  ui_status_warn "to set new passwords for every default account."
  ui_status_info ""
  ui_status_info "state snapshot:  ${state_json}"
  ui_status_info "installer log:   ${MANGOS_LOG_FILE}"
}
