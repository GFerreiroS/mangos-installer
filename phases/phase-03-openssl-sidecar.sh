#!/usr/bin/env bash
# mangos-installer — phase 03: build OpenSSL 1.1 sidecar
# SPDX-License-Identifier: GPL-2.0-only
# See CLAUDE.md for design, README.md for usage
# Stub for milestone 1; full implementation lands in milestone 2.

run_phase_03() {
  MANGOS_CURRENT_PHASE="phase-03-openssl-sidecar"
  if state_has_completed "$MANGOS_CURRENT_PHASE"; then
    ui_phase_header 3 14 "OpenSSL 1.1 sidecar (already done — skipping)"
    return 0
  fi
  ui_phase_header 3 14 "OpenSSL 1.1 sidecar"
  ui_status_info "stub: build openssl-1.1.1w under ~/mangos/opt/openssl-1.1 (rpath-wired) — milestone 2"
  state_mark_complete "$MANGOS_CURRENT_PHASE"
}
