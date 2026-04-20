#!/usr/bin/env bash
# mangos-installer — OS, arch, RAM, disk detection
# SPDX-License-Identifier: GPL-2.0-only
# See CLAUDE.md for design, README.md for usage
# shellcheck shell=bash

platform_detect_os() {
  if [[ ! -f /etc/os-release ]]; then
    die "cannot detect OS: /etc/os-release missing"
  fi
  local id="" version_id="" k v
  while IFS='=' read -r k v; do
    v="${v%\"}"; v="${v#\"}"
    case "$k" in
      ID)         id="$v" ;;
      VERSION_ID) version_id="$v" ;;
    esac
  done < /etc/os-release
  MANGOS_OS_ID="${id:-unknown}"
  MANGOS_OS_VERSION="${version_id:-unknown}"
  export MANGOS_OS_ID MANGOS_OS_VERSION
}

platform_detect_arch() {
  MANGOS_ARCH="$(uname -m)"
  export MANGOS_ARCH
}

# Returns: 0 supported, 1 in warn list, 2 unsupported.
platform_check_supported() {
  local key="${MANGOS_OS_ID}:${MANGOS_OS_VERSION}"
  local d
  for d in "${SUPPORTED_DISTROS[@]}"; do
    [[ "$d" == "$key" ]] && return 0
  done
  for d in "${WARN_DISTROS[@]}"; do
    [[ "$d" == "$key" ]] && return 1
  done
  return 2
}

platform_arch_supported() {
  local a
  for a in "${SUPPORTED_ARCHS[@]}"; do
    [[ "$a" == "$MANGOS_ARCH" ]] && return 0
  done
  return 1
}

platform_ram_gb() {
  awk '/^MemTotal:/ { printf "%d\n", $2/1024/1024 }' /proc/meminfo
}

# platform_build_parallelism — reasonable -j value for cmake / make builds.
# >=8GB RAM: full nproc; 4-8GB: half nproc (min 1); <4GB: 2.
platform_build_parallelism() {
  local ram_gb nproc_
  ram_gb=$(platform_ram_gb)
  nproc_=$(nproc 2>/dev/null || echo 2)
  if   (( ram_gb >= 8 )); then printf '%s\n' "$nproc_"
  elif (( ram_gb >= 4 )); then printf '%s\n' "$(( nproc_ / 2 > 0 ? nproc_ / 2 : 1 ))"
  else                         printf '%s\n' "2"
  fi
}

# platform_disk_gb <path> — free GB at the closest existing ancestor of <path>.
platform_disk_gb() {
  local path="$1" p="$1"
  while [[ ! -d "$p" ]] && [[ "$p" != "/" ]]; do
    p=$(dirname -- "$p")
  done
  df -BG --output=avail -- "$p" 2>/dev/null | tail -n 1 | tr -dc '0-9'
}
