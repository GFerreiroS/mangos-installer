#!/usr/bin/env bash
# mangos-installer — phase 09: copy built binaries into ~/mangos/<realm>/{bin,gamedata}
# SPDX-License-Identifier: GPL-2.0-only
# See CLAUDE.md for design, README.md for usage
# Stub for milestone 1; full implementation lands in milestone 2.

run_phase_09() {
  MANGOS_CURRENT_PHASE="phase-09-install-binaries"
  if state_has_completed "$MANGOS_CURRENT_PHASE"; then
    ui_phase_header 9 14 "install binaries (already done — skipping)"
    return 0
  fi
  ui_phase_header 9 14 "install binaries"
  ui_status_info "stub: copy mangosd/realmd/extractors and set perms (0755 / 0640) — milestone 2"
  state_mark_complete "$MANGOS_CURRENT_PHASE"
}
