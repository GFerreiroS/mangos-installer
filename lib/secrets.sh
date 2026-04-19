#!/usr/bin/env bash
# mangos-installer — root-owned credentials file (0600)
# SPDX-License-Identifier: GPL-2.0-only
# See CLAUDE.md for design, README.md for usage
# shellcheck shell=bash
#
# Lives at /etc/mangos-installer/secrets.env. Same flat KEY="value" format
# as config.env but writable only by root. Reuses _kv_set / _kv_get from
# lib/config.sh, which the runner sources before this file.

secrets_set() { _kv_set "${MANGOS_SECRETS_FILE:?MANGOS_SECRETS_FILE not set}" "$1" "$2"; }
secrets_get() { _kv_get "${MANGOS_SECRETS_FILE:?MANGOS_SECRETS_FILE not set}" "$1"; }

# secrets_init — make sure the directory and file exist with the right perms.
secrets_init() {
  local sf="${MANGOS_SECRETS_FILE:?MANGOS_SECRETS_FILE not set}"
  local sd
  sd=$(dirname -- "$sf")
  install -d -m 0700 -o root -g root -- "$sd"
  if [[ ! -f "$sf" ]]; then
    install -m 0600 -o root -g root /dev/null "$sf"
  else
    chmod 0600 -- "$sf"
    chown root:root -- "$sf" 2>/dev/null || true
  fi
}
