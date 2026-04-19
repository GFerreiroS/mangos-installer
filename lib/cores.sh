#!/usr/bin/env bash
# mangos-installer — per-core configuration
# SPDX-License-Identifier: GPL-2.0-only
# See CLAUDE.md for design, README.md for usage
# shellcheck shell=bash
#
# Only the "zero" core (Vanilla 1.12.x) is implemented. one/two/three are
# stubbed and rejected at preflight; this file documents what each core
# would need so a future contributor can wire them up.

# Returns: 0 supported, 1 known but unimplemented, 2 unknown.
core_supported() {
  case "$1" in
    zero)          return 0 ;;
    one|two|three) return 1 ;;
    *)             return 2 ;;
  esac
}

core_describe() {
  case "$1" in
    zero)  echo "MaNGOS Zero (Vanilla 1.12.x)" ;;
    one)   echo "MaNGOS One (TBC 2.4.3) — not yet implemented" ;;
    two)   echo "MaNGOS Two (WotLK 3.3.5) — not yet implemented" ;;
    three) echo "MaNGOS Three (Cataclysm 4.3.4) — not yet implemented" ;;
    *)     echo "unknown core" ;;
  esac
}

core_repo() {
  case "$1" in
    zero) printf '%s\n' "$MANGOS_ZERO_REPO" ;;
    *)    return 1 ;;
  esac
}

core_database_repo() {
  case "$1" in
    zero) printf '%s\n' "$MANGOS_ZERO_DB_REPO" ;;
    *)    return 1 ;;
  esac
}

# CMake flags for the named core (used by phase 8 in milestone 2).
core_cmake_flags() {
  case "$1" in
    zero)
      printf '%s\n' \
        "-DBUILD_MANGOSD=1" \
        "-DBUILD_REALMD=1" \
        "-DBUILD_TOOLS=1" \
        "-DUSE_STORMLIB=1" \
        "-DSCRIPT_LIB_ELUNA=1" \
        "-DSCRIPT_LIB_SD3=1" \
        "-DPLAYERBOTS=1" \
        "-DPCH=1"
      ;;
    *) return 1 ;;
  esac
}
