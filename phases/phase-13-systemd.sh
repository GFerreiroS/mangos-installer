#!/usr/bin/env bash
# mangos-installer — phase 13: install systemd unit + template, enable per-realm instance
# SPDX-License-Identifier: GPL-2.0-only
# See CLAUDE.md for design, README.md for usage
# Stub for milestone 1; full implementation lands in milestone 3.

run_phase_13() {
  MANGOS_CURRENT_PHASE="phase-13-systemd"
  if state_has_completed "$MANGOS_CURRENT_PHASE"; then
    ui_phase_header 13 14 "systemd (already done — skipping)"
    return 0
  fi
  ui_phase_header 13 14 "systemd"
  ui_status_info "stub: install templates/mangos-*.service; daemon-reload; enable per-realm — milestone 3"
  state_mark_complete "$MANGOS_CURRENT_PHASE"
}
