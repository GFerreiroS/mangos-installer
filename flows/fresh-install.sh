#!/usr/bin/env bash
# mangos-installer — fresh install flow
# SPDX-License-Identifier: GPL-2.0-only
# See CLAUDE.md for design, README.md for usage
# shellcheck shell=bash disable=SC2154
#
# Sourced by phases/runner.sh; expects all libraries already loaded.
# Walks phase 0 (preflight, fully implemented) followed by phases 1–14.
# In milestone 1 phases 1–14 are stubs that print "not implemented".

ui_print_banner "mangos installer ${INSTALLER_VERSION} — fresh install"

# Phase 0 — preflight + interactive configuration
# shellcheck source=../phases/phase-00-preflight.sh
. "$MANGOS_INSTALLER_DIR/phases/phase-00-preflight.sh"
run_phase_00

# Phases 1–14 — stubs in milestone 1
PHASES=(
  "phase-01-user-and-dirs"
  "phase-02-apt-deps"
  "phase-03-openssl-sidecar"
  "phase-04-gcc-available"
  "phase-05-mariadb"
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

for p in "${PHASES[@]}"; do
  # shellcheck disable=SC1090
  . "$MANGOS_INSTALLER_DIR/phases/${p}.sh"
  num="${p#phase-}"
  num="${num%%-*}"
  fn="run_phase_${num}"
  "$fn"
done

ui_print_banner "milestone 1 complete: phase 0 + 14 stubs walked"
ui_status_info "config:  $MANGOS_CONFIG_FILE"
ui_status_info "secrets: $MANGOS_SECRETS_FILE"
ui_status_info "state:   $MANGOS_STATE_FILE"
ui_status_info "log:     $MANGOS_LOG_FILE"
ui_status_info "next milestones will replace phases 1–14 with real implementations."
