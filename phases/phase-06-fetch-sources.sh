#!/usr/bin/env bash
# mangos-installer — phase 06: git clone server + database repos at pinned ref
# SPDX-License-Identifier: GPL-2.0-only
# See CLAUDE.md for design, README.md for usage
# Stub for milestone 1; full implementation lands in milestone 2.

run_phase_06() {
  MANGOS_CURRENT_PHASE="phase-06-fetch-sources"
  if state_has_completed "$MANGOS_CURRENT_PHASE"; then
    ui_phase_header 6 14 "fetch sources (already done — skipping)"
    return 0
  fi
  ui_phase_header 6 14 "fetch sources"
  ui_status_info "stub: clone mangoszero/server + database (latest tag, fallback to pinned ref) — milestone 2"
  state_mark_complete "$MANGOS_CURRENT_PHASE"
}
