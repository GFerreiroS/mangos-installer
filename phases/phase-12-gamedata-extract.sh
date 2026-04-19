#!/usr/bin/env bash
# mangos-installer — phase 12: extract DBC, maps, mmaps, vmaps from MPQ archives
# SPDX-License-Identifier: GPL-2.0-only
# See CLAUDE.md for design, README.md for usage
# Stub for milestone 1; full implementation lands in milestone 3.

run_phase_12() {
  MANGOS_CURRENT_PHASE="phase-12-gamedata-extract"
  if state_has_completed "$MANGOS_CURRENT_PHASE"; then
    ui_phase_header 12 14 "gamedata extract (already done — skipping)"
    return 0
  fi
  ui_phase_header 12 14 "gamedata extract"
  ui_status_info "stub: drive ExtractResources.sh non-interactively; expect 30 min – 2 h — milestone 3"
  state_mark_complete "$MANGOS_CURRENT_PHASE"
}
