#!/usr/bin/env bash
# mangos-installer — phase 04: ensure gcc-11 / g++-11 available
# SPDX-License-Identifier: GPL-2.0-only
# See CLAUDE.md for design, README.md for usage
# Stub for milestone 1; full implementation lands in milestone 2.

run_phase_04() {
  MANGOS_CURRENT_PHASE="phase-04-gcc-available"
  if state_has_completed "$MANGOS_CURRENT_PHASE"; then
    ui_phase_header 4 14 "gcc-11 available (already done — skipping)"
    return 0
  fi
  ui_phase_header 4 14 "gcc-11 available"
  ui_status_info "stub: install gcc-11/g++-11 if needed; do NOT alter system default — milestone 2"
  state_mark_complete "$MANGOS_CURRENT_PHASE"
}
