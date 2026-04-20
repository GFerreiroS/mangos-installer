#!/usr/bin/env bash
# mangos-installer — phase 04: ensure a working gcc-11 / g++-11 is available
# SPDX-License-Identifier: GPL-2.0-only
# See CLAUDE.md for design, README.md for usage
# shellcheck disable=SC2154
#
# MaNGOS Zero does not build cleanly with GCC 12+. Rather than rewire the
# system default with update-alternatives (which breaks unrelated packages),
# we simply ensure gcc-11 / g++-11 are installed and pin them at the CMake
# invocation in phase 8 via -DCMAKE_C_COMPILER / -DCMAKE_CXX_COMPILER.
#
# Community fix credit: rogical (forum thread on the Ubuntu 22.04 guide).

run_phase_04() {
  MANGOS_CURRENT_PHASE="phase-04-gcc-available"
  ui_phase_header 4 14 "gcc-11 available"

  if state_has_completed "$MANGOS_CURRENT_PHASE"; then
    ui_status_ok "already done — skipping"
    return 0
  fi

  privilege_require_root

  local system_cc_ver
  system_cc_ver=$(gcc -dumpfullversion -dumpversion 2>/dev/null || echo "unknown")
  ui_status_info "system gcc: ${system_cc_ver}"

  local cc="gcc-11" cxx="g++-11"

  if ! command -v "$cc" >/dev/null 2>&1 || ! command -v "$cxx" >/dev/null 2>&1; then
    ui_status_info "installing gcc-11 / g++-11..."
    DEBIAN_FRONTEND=noninteractive apt-get install -y -qq --no-install-recommends \
      -- gcc-11 g++-11 >>"$MANGOS_LOG_FILE" 2>&1 \
      || die "failed to install gcc-11 / g++-11 (see $MANGOS_LOG_FILE)"
  fi

  local cc_ver cxx_ver
  cc_ver=$("$cc"   -dumpfullversion -dumpversion 2>/dev/null || true)
  cxx_ver=$("$cxx" -dumpfullversion -dumpversion 2>/dev/null || true)
  [[ -n "$cc_ver"  ]] || die "gcc-11 not usable after install"
  [[ -n "$cxx_ver" ]] || die "g++-11 not usable after install"

  MANGOS_CC=$(command -v "$cc")
  MANGOS_CXX=$(command -v "$cxx")
  export MANGOS_CC MANGOS_CXX
  config_set MANGOS_CC  "$MANGOS_CC"
  config_set MANGOS_CXX "$MANGOS_CXX"

  ui_status_ok "gcc-11 at $MANGOS_CC (version $cc_ver)"
  ui_status_ok "g++-11 at $MANGOS_CXX (version $cxx_ver)"
  ui_status_info "system default gcc (${system_cc_ver}) left untouched — no update-alternatives"

  state_mark_complete "$MANGOS_CURRENT_PHASE"
}
