#!/usr/bin/env bash
# mangos-installer — phase 07: apply DB schemas (replaces upstream InstallDatabase.sh)
# SPDX-License-Identifier: GPL-2.0-only
# See CLAUDE.md for design, README.md for usage
# Stub for milestone 1; full implementation lands in milestone 2.

run_phase_07() {
  MANGOS_CURRENT_PHASE="phase-07-db-schemas"
  if state_has_completed "$MANGOS_CURRENT_PHASE"; then
    ui_phase_header 7 14 "DB schemas (already done — skipping)"
    return 0
  fi
  ui_phase_header 7 14 "DB schemas"
  ui_status_info "stub: create+populate auth/character/world DBs via direct mysql calls — milestone 2"
  state_mark_complete "$MANGOS_CURRENT_PHASE"
}
