#!/usr/bin/env bash
# mangos-installer — curl wrappers, background download, protocol validation
# SPDX-License-Identifier: GPL-2.0-only
# See CLAUDE.md for design, README.md for usage
# shellcheck shell=bash

# Returns: 0 secure (https/sftp), 1 insecure but supported (http/ftp),
#          2 unrecognized.
download_validate_protocol() {
  local url="$1"
  local proto="${url%%://*}"
  case "${proto,,}" in
    https|sftp) return 0 ;;
    http|ftp)   return 1 ;;
    *)          return 2 ;;
  esac
}

# download_file <url> <dest>
# Resumes if <dest> exists. Writes to a .part file then renames.
download_file() {
  local url="$1" dest="$2"
  mkdir -p -- "$(dirname -- "$dest")"
  local part="${dest}.part"
  if [[ -f "$dest" ]] && [[ ! -f "$part" ]]; then
    cp -f -- "$dest" "$part"
  fi
  curl -fL --retry 3 --retry-delay 5 --retry-connrefused \
    --connect-timeout 15 --speed-limit 1 --speed-time 60 \
    -C - -o "$part" -- "$url"
  mv -- "$part" "$dest"
}

# download_background <url> <dest> <pidfile>
# Writes the PID to <pidfile> and the curl exit code to <pidfile>.exit when done.
download_background() {
  local url="$1" dest="$2" pidfile="$3"
  local exitfile="${pidfile}.exit"
  mkdir -p -- "$(dirname -- "$dest")" "$(dirname -- "$pidfile")"
  rm -f -- "$exitfile"
  (
    set +e
    mkdir -p -- "$(dirname -- "$exitfile")"
    download_file "$url" "$dest" >>"${MANGOS_LOG_FILE:-/dev/null}" 2>&1
    printf '%d\n' "$?" > "$exitfile"
  ) &
  printf '%d\n' "$!" > "$pidfile"
  log_info "background download started: pid=$! url=$url dest=$dest"
}

# download_wait <pidfile> — blocks until the download finishes; prints exit code.
download_wait() {
  local pidfile="$1"
  local exitfile="${pidfile}.exit"
  if [[ ! -f "$pidfile" ]]; then
    log_error "download_wait: missing pidfile $pidfile"
    printf '%d\n' 2
    return 0
  fi
  local pid
  pid=$(cat -- "$pidfile")
  while kill -0 -- "$pid" 2>/dev/null; do
    sleep 5
  done
  if [[ -f "$exitfile" ]]; then
    cat -- "$exitfile"
  else
    printf '%d\n' 1
  fi
}
