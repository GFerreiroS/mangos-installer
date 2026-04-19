#!/usr/bin/env bash
# mangos-installer — phase 08: cmake configure + make + make install (per realm)
# SPDX-License-Identifier: GPL-2.0-only
# See CLAUDE.md for design, README.md for usage
# Stub for milestone 1; full implementation lands in milestone 2.

run_phase_08() {
  MANGOS_CURRENT_PHASE="phase-08-build"
  if state_has_completed "$MANGOS_CURRENT_PHASE"; then
    ui_phase_header 8 14 "build (already done — skipping)"
    return 0
  fi
  ui_phase_header 8 14 "build"
  ui_status_info "stub: cmake with explicit gcc-11 + sidecar OpenSSL paths; auto-tuned -j — milestone 2"
  state_mark_complete "$MANGOS_CURRENT_PHASE"
}
