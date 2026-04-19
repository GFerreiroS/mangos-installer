#!/usr/bin/env bash
# mangos-installer — phase 10: generate runtime .conf files from .conf.dist templates
# SPDX-License-Identifier: GPL-2.0-only
# See CLAUDE.md for design, README.md for usage
# Stub for milestone 1; full implementation lands in milestone 2.

run_phase_10() {
  MANGOS_CURRENT_PHASE="phase-10-configs"
  if state_has_completed "$MANGOS_CURRENT_PHASE"; then
    ui_phase_header 10 14 "configs (already done — skipping)"
    return 0
  fi
  ui_phase_header 10 14 "configs"
  ui_status_info "stub: inject DB creds, paths, realm info into mangosd.conf/realmd.conf — milestone 2"
  state_mark_complete "$MANGOS_CURRENT_PHASE"
}
