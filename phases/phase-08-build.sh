#!/usr/bin/env bash
# mangos-installer — phase 08: cmake configure + build + install (per-realm)
# SPDX-License-Identifier: GPL-2.0-only
# See CLAUDE.md for design, README.md for usage
# shellcheck disable=SC2154
#
# Explicit CMake compiler pin (MANGOS_CC / MANGOS_CXX set by phase 4) and
# explicit OpenSSL paths (set by phase 3). The OpenSSL 1.1 libs were
# rpath'd during phase 3, so the resulting mangosd / realmd pick up the
# sidecar at runtime without any LD_LIBRARY_PATH or ld.so.conf.d entry.
#
# make install lands under $BUILD_DIR/install/; phase 9 copies the pieces
# into the realm's bin/ and gamedata/ directories.

run_phase_08() {
  MANGOS_CURRENT_PHASE="phase-08-build"
  ui_phase_header 8 14 "build"

  if state_has_completed "$MANGOS_CURRENT_PHASE"; then
    ui_status_ok "already done — skipping"
    return 0
  fi

  mangos_user_exists || die "mangos user missing (phase 1 must run first)"
  : "${MANGOS_REALM_NAME:?MANGOS_REALM_NAME not set}"
  : "${MANGOS_REALM_CORE:?MANGOS_REALM_CORE not set}"

  local mangos_cc mangos_cxx openssl_prefix
  mangos_cc="${MANGOS_CC:-$(config_get MANGOS_CC)}"
  mangos_cxx="${MANGOS_CXX:-$(config_get MANGOS_CXX)}"
  openssl_prefix="${OPENSSL_PREFIX:-$(config_get OPENSSL_PREFIX)}"
  [[ -x "$mangos_cc"  ]] || die "MANGOS_CC not set or not executable (phase 4 must run first)"
  [[ -x "$mangos_cxx" ]] || die "MANGOS_CXX not set or not executable (phase 4 must run first)"
  [[ -d "$openssl_prefix/lib" ]] || die "OPENSSL_PREFIX missing (phase 3 must run first)"

  local realm_dir="$MANGOS_ROOT/$MANGOS_REALM_NAME"
  local src="${realm_dir}/source"
  local build="${realm_dir}/build"
  local install_prefix="${build}/install"
  [[ -d "$src" ]] || die "source tree missing at $src (phase 6 must run first)"

  local parallel
  parallel=$(platform_build_parallelism)
  ui_status_info "build parallelism: -j${parallel}"

  local -a extra_flags
  mapfile -t extra_flags < <(core_cmake_flags "$MANGOS_REALM_CORE") \
    || die "no CMake flags for core '$MANGOS_REALM_CORE'"

  _phase_08_run_build \
    "$src" "$build" "$install_prefix" \
    "$mangos_cc" "$mangos_cxx" "$openssl_prefix" \
    "$parallel" "${extra_flags[@]}"

  # Sanity check: mangosd + realmd should exist under install_prefix/bin.
  [[ -x "$install_prefix/bin/mangosd" ]] || die "build did not produce mangosd"
  [[ -x "$install_prefix/bin/realmd"  ]] || die "build did not produce realmd"

  ui_status_ok "build succeeded; artifacts at $install_prefix"
  state_mark_complete "$MANGOS_CURRENT_PHASE"
}

_phase_08_run_build() {
  local src="$1" build="$2" install_prefix="$3"
  local cc="$4" cxx="$5" openssl_prefix="$6"
  local parallel="$7"
  shift 7
  local -a extra=( "$@" )

  local start_ts end_ts
  start_ts=$(date +%s)

  local script
  script=$(mktemp --tmpdir "mi-mangos-build.XXXXXX.sh")
  {
    printf '#!/usr/bin/env bash\n'
    printf 'set -euo pipefail\n'
    printf 'cd %q\n' "$src"
    printf 'install -d -- %q\n' "$build"
    printf 'cmake -S %q -B %q \\\n' "$src" "$build"
    printf '  -DCMAKE_BUILD_TYPE=Release \\\n'
    printf '  -DCMAKE_C_COMPILER=%q \\\n' "$cc"
    printf '  -DCMAKE_CXX_COMPILER=%q \\\n' "$cxx"
    printf '  -DOPENSSL_ROOT_DIR=%q \\\n'       "$openssl_prefix"
    printf '  -DOPENSSL_INCLUDE_DIR=%q \\\n'    "$openssl_prefix/include"
    printf '  -DOPENSSL_CRYPTO_LIBRARY=%q \\\n' "$openssl_prefix/lib/libcrypto.so.1.1"
    printf '  -DOPENSSL_SSL_LIBRARY=%q \\\n'    "$openssl_prefix/lib/libssl.so.1.1"
    printf '  -DCMAKE_INSTALL_PREFIX=%q' "$install_prefix"
    local f
    for f in "${extra[@]}"; do
      printf ' \\\n  %q' "$f"
    done
    printf '\n'
    printf 'cmake --build %q -- -j%s\n' "$build" "$parallel"
    printf 'cmake --install %q\n' "$build"
  } > "$script"
  chmod 0755 -- "$script"

  ui_status_info "configuring + building mangos (this takes ~15–40 min)..."
  if ! run_script_as_mangos "$script" >>"$MANGOS_LOG_FILE" 2>&1; then
    rm -f -- "$script"
    die "mangos build failed (see $MANGOS_LOG_FILE)"
  fi
  rm -f -- "$script"

  end_ts=$(date +%s)
  ui_status_ok "build duration: $(( end_ts - start_ts ))s"
}
