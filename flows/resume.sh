#!/usr/bin/env bash
# mangos-installer — resume a partially complete install
# SPDX-License-Identifier: GPL-2.0-only
# See CLAUDE.md for design, README.md for usage
# shellcheck shell=bash disable=SC2154
#
# The state guards at the top of every run_phase_NN already skip
# completed phases, so "resume" is really just "run fresh-install
# against the existing config + state". This flow exists for intent
# clarity: operator says "resume" when they know an install was
# interrupted; menu.sh routes them here instead of re-prompting phase 0.

ui_print_banner "mangos installer ${INSTALLER_VERSION} — resume"

config_load

ui_status_info "resuming against existing install at $MANGOS_ROOT"
ui_status_info "(phases already complete will be skipped automatically)"

# Re-dispatch into fresh-install. Phase 0 short-circuits via its own
# state-has-completed guard, and per-realm phases hydrate from the
# persisted MANGOS_CURRENT_REALM pointer.
# shellcheck disable=SC1090
. "$MANGOS_INSTALLER_DIR/flows/fresh-install.sh"
