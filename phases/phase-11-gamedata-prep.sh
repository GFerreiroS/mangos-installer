#!/usr/bin/env bash
# mangos-installer — phase 11: gamedata source resolution (path / URL wait / manual)
# SPDX-License-Identifier: GPL-2.0-only
# See CLAUDE.md for design, README.md for usage
# Stub for milestone 1; full implementation lands in milestone 3.

run_phase_11() {
  MANGOS_CURRENT_PHASE="phase-11-gamedata-prep"
  if state_has_completed "$MANGOS_CURRENT_PHASE"; then
    ui_phase_header 11 14 "gamedata prep (already done — skipping)"
    return 0
  fi
  ui_phase_header 11 14 "gamedata prep"
  ui_status_info "stub: validate path / wait on background download / instruct manual placement — milestone 3"
  state_mark_complete "$MANGOS_CURRENT_PHASE"
}
