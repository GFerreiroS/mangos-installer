#!/usr/bin/env bash
# mangos-installer — fresh install flow
# SPDX-License-Identifier: GPL-2.0-only
# See CLAUDE.md for design, README.md for usage
# shellcheck shell=bash disable=SC2154
#
# Sourced by phases/runner.sh; expects all libraries already loaded.
# Walks phase 0 (preflight), phases 1-5 (global), then phases 6-14
# (per-realm). state_json_write runs after every phase so external
# consumers always see a fresh snapshot.

ui_print_banner "mangos installer ${INSTALLER_VERSION} — fresh install"

# Phase 0 — preflight + interactive configuration
# shellcheck source=../phases/phase-00-preflight.sh
. "$MANGOS_INSTALLER_DIR/phases/phase-00-preflight.sh"
run_phase_00
state_json_write || true

# Global phases (1-5) write to the global state file.
GLOBAL_PHASES=(
  "phase-01-user-and-dirs"
  "phase-02-apt-deps"
  "phase-03-openssl-sidecar"
  "phase-04-gcc-available"
  "phase-05-mariadb"
)

# Per-realm phases (6-14) write to <realm>.state. Multi-realm support
# (milestone 4) will loop over realms; milestones 2/3 use the single
# realm collected by preflight.
REALM_PHASES=(
  "phase-06-fetch-sources"
  "phase-07-db-schemas"
  "phase-08-build"
  "phase-09-install-binaries"
  "phase-10-configs"
  "phase-11-gamedata-prep"
  "phase-12-gamedata-extract"
  "phase-13-systemd"
  "phase-14-smoke"
)

_run_phases() {
  local p num fn
  for p in "$@"; do
    # shellcheck disable=SC1090
    . "$MANGOS_INSTALLER_DIR/phases/${p}.sh"
    num="${p#phase-}"
    num="${num%%-*}"
    fn="run_phase_${num}"
    "$fn"
    # Keep state.json fresh so external observers (CLAUDE.md § 5.7) can
    # poll after each phase without racing a write.
    state_json_write || true
  done
}

_run_phases "${GLOBAL_PHASES[@]}"

state_switch_to_realm "$MANGOS_REALM_NAME"
log_info "switched to per-realm state for '$MANGOS_REALM_NAME': $MANGOS_STATE_FILE"

_run_phases "${REALM_PHASES[@]}"

# Phase 14 prints its own success banner; nothing else to say here.
