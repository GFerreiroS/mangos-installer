#!/usr/bin/env bash
# mangos-installer — per-core configuration
# SPDX-License-Identifier: GPL-2.0-only
# See CLAUDE.md for design, README.md for usage
# shellcheck shell=bash
#
# Only the "zero" core (Vanilla 1.12.x) is implemented. one/two/three are
# stubbed and rejected at preflight.
#
# How to add a new core (for future contributors):
#
# 1. Update core_supported(): return 0 for the new core name.
# 2. Update core_describe(): add a user-visible description.
# 3. Update core_repo() and core_database_repo(): return the upstream
#    git URLs (e.g. github.com/mangosone/server for TBC 2.4.3).
# 4. Update core_cmake_flags(): return the CMake flag set the upstream
#    build system expects for that core. mangos-one/two/three each have
#    subtly different feature flags (e.g. PLAYERBOTS support varies).
# 5. Update lib/gamedata.sh: add _gamedata_required_mpqs_<core> and
#    _gamedata_forbidden_mpqs_<core> arrays. TBC (one) needs
#    expansion.MPQ; WotLK (two) needs expansion + lichking; Cataclysm
#    (three) uses a different archive format entirely (MPQ -> CASC)
#    so that core will likely need extra plumbing in gamedata.sh.
# 6. Update README.md's "Supported cores" section.
# 7. Add manual-testing steps for the new core in docs/MANUAL-TESTING.md.
#
# The preflight phase and the add-realm flow both gate on core_supported(),
# so the installer refuses to proceed for unimplemented cores and prints
# the message returned by core_describe().

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
    one)   echo "MaNGOS One (TBC 2.4.3) — not yet implemented; see lib/cores.sh for a porting checklist" ;;
    two)   echo "MaNGOS Two (WotLK 3.3.5) — not yet implemented; see lib/cores.sh for a porting checklist" ;;
    three) echo "MaNGOS Three (Cataclysm 4.3.4) — not yet implemented; CASC vs MPQ archives need separate plumbing" ;;
    *)     echo "unknown core '$1'" ;;
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
