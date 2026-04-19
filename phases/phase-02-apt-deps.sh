#!/usr/bin/env bash
# mangos-installer — phase 02: install apt dependencies
# SPDX-License-Identifier: GPL-2.0-only
# See CLAUDE.md for design, README.md for usage
# Stub for milestone 1; full implementation lands in milestone 2.

run_phase_02() {
  MANGOS_CURRENT_PHASE="phase-02-apt-deps"
  if state_has_completed "$MANGOS_CURRENT_PHASE"; then
    ui_phase_header 2 14 "apt dependencies (already done — skipping)"
    return 0
  fi
  ui_phase_header 2 14 "apt dependencies"
  ui_status_info "stub: single apt-get install with build deps + mariadb-server — milestone 2"
  state_mark_complete "$MANGOS_CURRENT_PHASE"
}
