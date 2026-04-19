#!/usr/bin/env bash
# mangos-installer — phase 14: start services and verify ports listening
# SPDX-License-Identifier: GPL-2.0-only
# See CLAUDE.md for design, README.md for usage
# Stub for milestone 1; full implementation lands in milestone 3.

run_phase_14() {
  MANGOS_CURRENT_PHASE="phase-14-smoke"
  if state_has_completed "$MANGOS_CURRENT_PHASE"; then
    ui_phase_header 14 14 "smoke test (already done — skipping)"
    return 0
  fi
  ui_phase_header 14 14 "smoke test"
  ui_status_info "stub: start mangos-realmd + mangos-mangosd@<realm>; verify ports 3724 + world — milestone 3"
  state_mark_complete "$MANGOS_CURRENT_PHASE"
}
