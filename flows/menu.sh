#!/usr/bin/env bash
# mangos-installer — management menu (shown on re-run against an existing install)
# SPDX-License-Identifier: GPL-2.0-only
# See CLAUDE.md for design, README.md for usage
# shellcheck shell=bash disable=SC2154
#
# The runner dispatches here whenever $MANGOS_ROOT/.installer/config.env
# already exists. Lists installed realms, global component presence, and
# offers operator actions.

ui_print_banner "mangos installer ${INSTALLER_VERSION} — management"

config_load

# --- summary ---------------------------------------------------------------

_menu_summary() {
  local realms realm count=0
  realms=$(state_list_realms)
  if [[ -n "$realms" ]]; then
    ui_status_info "installed realms:"
    while IFS= read -r realm; do
      [[ -z "$realm" ]] && continue
      local status
      status=$(config_get "REALM_${realm}_STATUS")
      ui_status_ok "  ${realm}  (${status:-unknown})"
      count=$(( count + 1 ))
    done <<< "$realms"
  else
    ui_status_warn "no realms in config.env (unexpected; re-run fresh-install)"
  fi

  local openssl_prefix db_mode db_host db_port
  openssl_prefix=$(config_get OPENSSL_PREFIX)
  db_mode=$(config_get DB_MODE)
  db_host=$(config_get DB_HOST)
  db_port=$(config_get DB_PORT)

  ui_status_info "global components:"
  if [[ -x "$openssl_prefix/bin/openssl" ]]; then
    local v
    v=$("$openssl_prefix/bin/openssl" version 2>/dev/null | awk '{print $2}')
    ui_status_ok "  OpenSSL 1.1 sidecar at $openssl_prefix (version $v)"
  else
    ui_status_warn "  OpenSSL 1.1 sidecar missing at $openssl_prefix"
  fi
  if [[ "$db_mode" == "local" ]] && command -v mariadb >/dev/null 2>&1; then
    ui_status_ok "  MariaDB (local): $(mariadb --version 2>/dev/null | awk '{print $3}' | sed 's/,$//')"
  elif [[ "$db_mode" == "remote" ]]; then
    ui_status_ok "  DB (remote): $db_host:$db_port"
  fi
  return "$count"
}

# --- option handling -------------------------------------------------------

_menu_prompt() {
  local realms realm_count
  realms=$(state_list_realms)
  realm_count=$(printf '%s\n' "$realms" | grep -c . || true)

  # When --flow was not set and the operator has set MANGOS_NONINTERACTIVE,
  # error out loudly rather than sitting on a prompt forever.
  if [[ "${MANGOS_NONINTERACTIVE:-0}" == "1" ]]; then
    die "non-interactive mode: pass --flow=<name> to pick a management action"
  fi

  ui_status_info ""
  ui_status_info "what would you like to do?"
  ui_status_info "  1) add a new realm"
  ui_status_info "  2) update an existing realm"
  ui_status_info "  3) uninstall a realm"
  ui_status_info "  4) uninstall everything"
  ui_status_info "  5) resume an interrupted install"
  ui_status_info "  6) exit"

  local choice
  while :; do
    read -rp "choice [6]: " choice
    choice="${choice:-6}"
    case "$choice" in
      1|2|3|4|5|6) break ;;
      *) printf 'please answer 1, 2, 3, 4, 5, or 6.\n' >&2 ;;
    esac
  done

  case "$choice" in
    1) MANGOS_FLOW="add-realm"       ;;
    2) MANGOS_FLOW="update-realm"    ;;
    3) MANGOS_FLOW="uninstall-realm" ;;
    4) MANGOS_FLOW="uninstall-all"   ;;
    5) MANGOS_FLOW="resume"          ;;
    6) ui_status_info "bye."; exit 0 ;;
  esac
  export MANGOS_FLOW
}

# ---------------------------------------------------------------------------

_menu_summary || true
_menu_prompt

# Dispatch the chosen flow at top level (outside any function) to avoid
# bash 5.x pop_var_context corruption when sourcing scripts inside a function.
# shellcheck disable=SC1090
[[ -n "${MANGOS_FLOW:-}" ]] && . "$MANGOS_INSTALLER_DIR/flows/${MANGOS_FLOW}.sh"
