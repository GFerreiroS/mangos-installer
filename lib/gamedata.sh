#!/usr/bin/env bash
# mangos-installer — gamedata validation and preparation
# SPDX-License-Identifier: GPL-2.0-only
# See CLAUDE.md for design, README.md for usage
# shellcheck shell=bash
#
# Stubs for milestone 1. Full implementation lands in milestone 3 along
# with the gamedata extraction phases.

# gamedata_validate_structure <path> [<core>]
# Real impl: walk up to 3 levels, find Data/common.MPQ, verify MPQs match
# the expected set for the core, reject expansion/lichking MPQs for "zero".
gamedata_validate_structure() {
  local path="$1" core="${2:-zero}"
  if [[ -z "$path" ]]; then
    log_error "gamedata_validate_structure: empty path"
    return 1
  fi
  log_info "gamedata_validate_structure stub: path=$path core=$core (always succeeds in milestone 1)"
  return 0
}

# gamedata_find_data_dir <path>
# Real impl: find the directory containing Data/ (handles nested archives).
gamedata_find_data_dir() {
  local path="$1"
  log_info "gamedata_find_data_dir stub: path=$path (returns input)"
  printf '%s\n' "$path"
}

# gamedata_move_to_realm <source> <realm>
# Real impl: mv or symlink from <source>/Data into ~/mangos/<realm>/gamedata/Data.
gamedata_move_to_realm() {
  log_warn "gamedata_move_to_realm: not implemented (milestone 3)"
  return 1
}
