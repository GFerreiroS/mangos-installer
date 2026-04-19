#!/usr/bin/env bash
# mangos-installer — phase 05: MariaDB setup (local) or remote DB validation
# SPDX-License-Identifier: GPL-2.0-only
# See CLAUDE.md for design, README.md for usage
# Stub for milestone 1; full implementation lands in milestone 2.

run_phase_05() {
  MANGOS_CURRENT_PHASE="phase-05-mariadb"
  if state_has_completed "$MANGOS_CURRENT_PHASE"; then
    ui_phase_header 5 14 "MariaDB (already done — skipping)"
    return 0
  fi
  ui_phase_header 5 14 "MariaDB"
  ui_status_info "stub: enable mariadb (local) or validate remote DB version + grants — milestone 2"
  state_mark_complete "$MANGOS_CURRENT_PHASE"
}
