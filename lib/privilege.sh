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
