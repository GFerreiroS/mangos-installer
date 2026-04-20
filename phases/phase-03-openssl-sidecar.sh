#!/usr/bin/env bash
# mangos-installer — phase 03: build + install OpenSSL 1.1.1w as a sidecar
# SPDX-License-Identifier: GPL-2.0-only
# See CLAUDE.md for design, README.md for usage
# shellcheck disable=SC2154
#
# Builds OpenSSL 1.1.1w into $OPENSSL_PREFIX (default:
# /home/mangos/mangos/opt/openssl-1.1). The build is wired with
#   LDFLAGS="-Wl,-rpath,$OPENSSL_PREFIX/lib"
# so the resulting libraries carry the sidecar path in rpath, meaning
# mangosd/realmd will find them at runtime without touching
# /etc/ld.so.conf.d/ or /usr/bin/openssl. The system OpenSSL 3 stays intact.
#
# Idempotent: if the target prefix already contains a working OpenSSL 1.1
# binary, the phase is a no-op.

run_phase_03() {
  MANGOS_CURRENT_PHASE="phase-03-openssl-sidecar"
  ui_phase_header 3 14 "OpenSSL 1.1 sidecar"

  if state_has_completed "$MANGOS_CURRENT_PHASE"; then
    ui_status_ok "already done — skipping"
    return 0
  fi

  local prefix="${OPENSSL_PREFIX:-$MANGOS_ROOT/opt/openssl-1.1}"
  export OPENSSL_PREFIX="$prefix"

  if _openssl_already_installed "$prefix"; then
    ui_status_ok "OpenSSL 1.1 already present at $prefix"
    state_mark_complete "$MANGOS_CURRENT_PHASE"
    return 0
  fi

  privilege_require_root
  mangos_user_exists || die "mangos user missing (phase 1 must run first)"

  local cache="$MANGOS_ROOT/.installer/build-cache"
  install -d -m 0755 -o "$MANGOS_USER" -g "$MANGOS_USER" -- "$cache"

  local tarball="$cache/openssl-${OPENSSL_SIDECAR_VERSION}.tar.gz"
  local src_dir="$cache/openssl-${OPENSSL_SIDECAR_VERSION}"

  _openssl_fetch   "$tarball"
  _openssl_verify  "$tarball"
  _openssl_extract "$tarball" "$cache" "$src_dir"
  _openssl_build   "$src_dir" "$prefix"
  _openssl_confirm "$prefix"

  ui_status_ok "OpenSSL 1.1 installed at $prefix"
  state_mark_complete "$MANGOS_CURRENT_PHASE"
}

# --- helpers -----------------------------------------------------------------

_openssl_already_installed() {
  local prefix="$1"
  [[ -x "$prefix/bin/openssl" ]] || return 1
  "$prefix/bin/openssl" version 2>/dev/null | grep -q '^OpenSSL 1\.1\.1'
}

_openssl_fetch() {
  local tarball="$1"
  if [[ -f "$tarball" ]]; then
    ui_status_ok "source tarball already cached: $(basename -- "$tarball")"
    return 0
  fi
  ui_status_info "downloading openssl-${OPENSSL_SIDECAR_VERSION}..."
  run_as_mangos "curl -fL --retry 3 --retry-delay 5 -o '$tarball' '$OPENSSL_SIDECAR_URL'" \
    >>"$MANGOS_LOG_FILE" 2>&1 \
    || die "openssl download failed (see $MANGOS_LOG_FILE)"
}

_openssl_verify() {
  local tarball="$1"
  ui_status_info "verifying SHA256..."
  local actual
  actual=$(sha256sum -- "$tarball" | awk '{ print $1 }')
  if [[ "$actual" != "$OPENSSL_SIDECAR_SHA256" ]]; then
    die "openssl SHA256 mismatch (expected=$OPENSSL_SIDECAR_SHA256 got=$actual)"
  fi
  ui_status_ok "SHA256 matches"
}

_openssl_extract() {
  local tarball="$1" cache="$2" src_dir="$3"
  if [[ -d "$src_dir" ]] && [[ -f "$src_dir/Configure" ]]; then
    ui_status_ok "source already extracted"
    return 0
  fi
  ui_status_info "extracting..."
  run_as_mangos "tar -xzf '$tarball' -C '$cache'" >>"$MANGOS_LOG_FILE" 2>&1 \
    || die "openssl extraction failed"
}

_openssl_build() {
  local src_dir="$1" prefix="$2"
  local parallel
  parallel=$(platform_build_parallelism)
  ui_status_info "building OpenSSL 1.1 (~5-15 min; parallel=$parallel)..."

  local script
  script=$(mktemp --tmpdir "mi-openssl-build.XXXXXX.sh")
  cat > "$script" <<BUILD
#!/usr/bin/env bash
set -euo pipefail
cd "$src_dir"
export LDFLAGS="-Wl,-rpath,$prefix/lib"
./config shared zlib --prefix="$prefix" --openssldir="$prefix"
make -j$parallel
make install_sw
BUILD
  chmod 0755 -- "$script"

  install -d -m 0755 -o "$MANGOS_USER" -g "$MANGOS_USER" -- "$prefix"

  if ! run_script_as_mangos "$script" >>"$MANGOS_LOG_FILE" 2>&1; then
    rm -f -- "$script"
    die "openssl build failed (see $MANGOS_LOG_FILE)"
  fi
  rm -f -- "$script"
}

_openssl_confirm() {
  local prefix="$1"
  [[ -f "$prefix/lib/libssl.so.1.1" ]]    || die "openssl install missing $prefix/lib/libssl.so.1.1"
  [[ -f "$prefix/lib/libcrypto.so.1.1" ]] || die "openssl install missing $prefix/lib/libcrypto.so.1.1"
  "$prefix/bin/openssl" version 2>/dev/null | grep -q '^OpenSSL 1\.1\.1' \
    || die "openssl binary version check failed"
}
