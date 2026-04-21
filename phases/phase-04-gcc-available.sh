#!/usr/bin/env bash
# mangos-installer — phase 04: ensure a suitable gcc / g++ is available
# SPDX-License-Identifier: GPL-2.0-only
# See CLAUDE.md for design, README.md for usage
# shellcheck disable=SC2154
#
# MaNGOS Zero builds best with GCC 11. On distros where gcc-11 is no longer
# packaged (Debian 13+), we fall back to the lowest available versioned
# compiler in the range 12–14 and pin it at the CMake invocation in phase 8
# via -DCMAKE_C_COMPILER / -DCMAKE_CXX_COMPILER.
#
# Community fix credit: rogical (forum thread on the Ubuntu 22.04 guide).

run_phase_04() {
  MANGOS_CURRENT_PHASE="phase-04-gcc-available"
  ui_phase_header 4 14 "gcc available"

  if state_has_completed "$MANGOS_CURRENT_PHASE"; then
    ui_status_ok "already done — skipping"
    return 0
  fi

  privilege_require_root

  local system_cc_ver
  system_cc_ver=$(gcc -dumpfullversion -dumpversion 2>/dev/null || echo "unknown")
  ui_status_info "system gcc: ${system_cc_ver}"

  local cc="" cxx="" ver=""
  # Prefer gcc-11; fall back to 12, 13, 14 in order.
  local candidate
  for candidate in 11 12 13 14; do
    if command -v "gcc-${candidate}" >/dev/null 2>&1 \
       && command -v "g++-${candidate}" >/dev/null 2>&1; then
      cc="gcc-${candidate}"; cxx="g++-${candidate}"
      break
    fi
    # Try to install it.
    if DEBIAN_FRONTEND=noninteractive apt-get install -y -qq --no-install-recommends \
         -- "gcc-${candidate}" "g++-${candidate}" >>"$MANGOS_LOG_FILE" 2>&1; then
      cc="gcc-${candidate}"; cxx="g++-${candidate}"
      break
    fi
  done

  [[ -n "$cc" ]] || die "could not find or install any of gcc-11/12/13/14 (see $MANGOS_LOG_FILE)"

  local cc_ver cxx_ver
  cc_ver=$("$cc"  -dumpfullversion -dumpversion 2>/dev/null || true)
  cxx_ver=$("$cxx" -dumpfullversion -dumpversion 2>/dev/null || true)
  [[ -n "$cc_ver"  ]] || die "$cc not usable after install"
  [[ -n "$cxx_ver" ]] || die "$cxx not usable after install"

  if [[ "$candidate" != "11" ]]; then
    ui_status_warn "gcc-11 not available; using gcc-${candidate} — build may need extra flags"
  fi

  MANGOS_CC=$(command -v "$cc")
  MANGOS_CXX=$(command -v "$cxx")
  export MANGOS_CC MANGOS_CXX
  config_set MANGOS_CC  "$MANGOS_CC"
  config_set MANGOS_CXX "$MANGOS_CXX"

  ui_status_ok "$cc at $MANGOS_CC (version $cc_ver)"
  ui_status_ok "$cxx at $MANGOS_CXX (version $cxx_ver)"
  ui_status_info "system default gcc (${system_cc_ver}) left untouched — no update-alternatives"

  state_mark_complete "$MANGOS_CURRENT_PHASE"
}
