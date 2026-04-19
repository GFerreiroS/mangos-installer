#!/usr/bin/env bash
# mangos-installer — archive detection and extraction
# SPDX-License-Identifier: GPL-2.0-only
# See CLAUDE.md for design, README.md for usage
# shellcheck shell=bash
#
# Detects format by extension first, then by `file --mime-type`. Installs
# unzip/p7zip-full/unrar on demand if missing and we are root.

# archive_detect_format <file> — prints format token; returns non-zero for "unknown".
archive_detect_format() {
  local f="$1"
  case "${f,,}" in
    *.tar.gz|*.tgz)         echo "tar.gz"  ; return 0 ;;
    *.tar.xz|*.txz)         echo "tar.xz"  ; return 0 ;;
    *.tar.bz2|*.tbz2|*.tbz) echo "tar.bz2" ; return 0 ;;
    *.tar)                  echo "tar"     ; return 0 ;;
    *.zip)                  echo "zip"     ; return 0 ;;
    *.7z)                   echo "7z"      ; return 0 ;;
    *.rar)                  echo "rar"     ; return 0 ;;
  esac
  if command -v file >/dev/null 2>&1; then
    local mime
    mime=$(file -b --mime-type -- "$f" 2>/dev/null || true)
    case "$mime" in
      application/gzip|application/x-gzip)    echo "tar.gz"  ; return 0 ;;
      application/x-xz)                       echo "tar.xz"  ; return 0 ;;
      application/x-bzip2)                    echo "tar.bz2" ; return 0 ;;
      application/x-tar)                      echo "tar"     ; return 0 ;;
      application/zip)                        echo "zip"     ; return 0 ;;
      application/x-7z-compressed)            echo "7z"      ; return 0 ;;
      application/vnd.rar|application/x-rar*) echo "rar"     ; return 0 ;;
    esac
  fi
  echo "unknown"
  return 1
}

_archive_ensure_tool() {
  local tool="$1" pkg="$2"
  command -v "$tool" >/dev/null 2>&1 && return 0
  if [[ $EUID -ne 0 ]]; then
    log_error "missing tool '$tool' (install package '$pkg' to extract)"
    return 1
  fi
  log_info "installing $pkg for $tool"
  DEBIAN_FRONTEND=noninteractive apt-get install -y -- "$pkg" >>"${MANGOS_LOG_FILE:-/dev/null}" 2>&1
}

# archive_extract <archive> <destdir>
archive_extract() {
  local archive="$1" destdir="$2"
  local fmt
  fmt=$(archive_detect_format "$archive") || true
  mkdir -p -- "$destdir"
  case "$fmt" in
    tar.gz)  tar -xzf "$archive" -C "$destdir" ;;
    tar.xz)  tar -xJf "$archive" -C "$destdir" ;;
    tar.bz2) tar -xjf "$archive" -C "$destdir" ;;
    tar)     tar -xf  "$archive" -C "$destdir" ;;
    zip)     _archive_ensure_tool unzip unzip || return 1
             unzip -q -o "$archive" -d "$destdir" ;;
    7z)      _archive_ensure_tool 7z p7zip-full || return 1
             7z x -bd -y -o"$destdir" "$archive" >/dev/null ;;
    rar)     _archive_ensure_tool unrar unrar || return 1
             unrar x -y -o+ "$archive" "$destdir/" >/dev/null ;;
    *)       log_error "unknown archive format for: $archive"; return 1 ;;
  esac
}
