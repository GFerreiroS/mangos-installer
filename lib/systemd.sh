#!/usr/bin/env bash
# mangos-installer — systemd unit installation + lifecycle helpers
# SPDX-License-Identifier: GPL-2.0-only
# See CLAUDE.md for design, README.md for usage
# shellcheck shell=bash
#
# Units live under /etc/systemd/system/. The realmd unit is single and
# shared across realms (one auth daemon per host on port 3724); the
# mangosd unit is a template, instantiated per realm.

readonly SYSTEMD_UNIT_DIR="/etc/systemd/system"
readonly SYSTEMD_TEMPLATES_REL="templates"

# systemd_install_units — copy realmd + template into /etc/systemd/system
# if missing (or contents differ) and run daemon-reload. Idempotent.
systemd_install_units() {
  privilege_require_root
  local src="$MANGOS_INSTALLER_DIR/$SYSTEMD_TEMPLATES_REL"
  local changed=0
  local f
  for f in "$src/mangos-realmd.service" "$src/mangos-mangosd@.service"; do
    [[ -f "$f" ]] || { log_error "missing template: $f"; return 1; }
    local base dest
    base=$(basename -- "$f")
    dest="$SYSTEMD_UNIT_DIR/$base"
    if [[ ! -f "$dest" ]] || ! cmp -s -- "$f" "$dest"; then
      install -m 0644 -o root -g root -- "$f" "$dest"
      changed=1
      log_info "installed unit: $dest"
    fi
  done
  if (( changed )); then
    systemctl daemon-reload
    log_info "systemctl daemon-reload"
  fi
  return 0
}

# systemd_have — returns 0 if systemctl is present AND usable (pid 1 is
# systemd, or we can talk to the system manager).
systemd_have() {
  command -v systemctl >/dev/null 2>&1 || return 1
  systemctl is-system-running --quiet 2>/dev/null || \
    systemctl list-units --type=service --no-legend >/dev/null 2>&1
}

# port_in_use <port> — returns 0 if the TCP port is already bound on
# this host. Used by phase 0 to warn about collisions before install.
port_in_use() {
  local port="$1"
  if command -v ss >/dev/null 2>&1; then
    ss -lnt "sport = :${port}" 2>/dev/null | tail -n +2 | grep -q .
  elif command -v netstat >/dev/null 2>&1; then
    netstat -lnt 2>/dev/null | awk '{print $4}' | grep -qE "[.:]${port}$"
  else
    return 1
  fi
}

systemd_enable()  { systemctl enable  -- "$@" >/dev/null; }
systemd_disable() { systemctl disable -- "$@" >/dev/null 2>&1 || true; }
systemd_start()   { systemctl start   -- "$@"; }
systemd_stop()    { systemctl stop    -- "$@" 2>/dev/null || true; }
systemd_is_active()  { systemctl is-active  --quiet -- "$1"; }
systemd_is_enabled() { systemctl is-enabled --quiet -- "$1"; }

# systemd_journal_tail <unit> [<lines>] — print last <lines> of journalctl
# for a unit (default 50) to stderr. No-op if journalctl unavailable.
systemd_journal_tail() {
  local unit="$1" lines="${2:-50}"
  command -v journalctl >/dev/null 2>&1 || return 0
  journalctl -n "$lines" --no-pager -u "$unit" >&2 2>/dev/null || true
}

# systemd_wait_port <port> <timeout-seconds>
# Polls every second for an LISTEN socket on the given TCP port (ss).
# Returns 0 on success, 1 on timeout. Uses `ss` (iproute2) which is in
# phase-02's dep list (net-tools covers ss via iproute2 coming in by
# default on modern distros; we fall back to netstat).
systemd_wait_port() {
  local port="$1" timeout="${2:-30}"
  local deadline=$(( $(date +%s) + timeout ))
  while (( $(date +%s) < deadline )); do
    if command -v ss >/dev/null 2>&1; then
      ss -lnt "sport = :${port}" 2>/dev/null | tail -n +2 | grep -q . && return 0
    elif command -v netstat >/dev/null 2>&1; then
      netstat -lnt 2>/dev/null | awk '{print $4}' | grep -qE "[.:]${port}$" && return 0
    fi
    sleep 1
  done
  return 1
}
