#!/usr/bin/env bash
# mangos-installer — root checks and run-as-mangos helpers
# SPDX-License-Identifier: GPL-2.0-only
# See CLAUDE.md for design, README.md for usage
# shellcheck shell=bash

privilege_is_root() { [[ $EUID -eq 0 ]]; }

privilege_require_root() {
  privilege_is_root || die "this installer must be run as root (try: sudo bash install.sh)"
}

# run_as_mangos "<command string>"
# Until phase 1 creates the mangos user, runs inline with a warning.
run_as_mangos() {
  local user="${MANGOS_USER:-${MANGOS_DEFAULT_USER:-mangos}}"
  if id -u "$user" >/dev/null 2>&1; then
    sudo -u "$user" -H bash -c "$*"
  else
    log_warn "run_as_mangos: user '$user' does not exist yet; running inline as $(id -un)"
    bash -c "$*"
  fi
}

# run_script_as_mangos <script-path> [args...]
# Executes a pre-written script as the mangos user. Avoids the shell-quoting
# hazards of run_as_mangos "<long command>" for multi-line build steps.
run_script_as_mangos() {
  local script="$1"
  shift
  local user="${MANGOS_USER:-${MANGOS_DEFAULT_USER:-mangos}}"
  [[ -r "$script" ]] || die "run_script_as_mangos: script not readable: $script"
  if id -u "$user" >/dev/null 2>&1; then
    sudo -u "$user" -H bash -- "$script" "$@"
  else
    die "run_script_as_mangos: user '$user' does not exist (phase 1 must run first)"
  fi
}

# mangos_user_exists — lightweight check used by phase idempotence guards.
mangos_user_exists() {
  local user="${MANGOS_USER:-${MANGOS_DEFAULT_USER:-mangos}}"
  id -u "$user" >/dev/null 2>&1
}
