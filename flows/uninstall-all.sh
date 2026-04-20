#!/usr/bin/env bash
# mangos-installer — remove every realm, the systemd units, and secrets
# SPDX-License-Identifier: GPL-2.0-only
# See CLAUDE.md for design, README.md for usage
# shellcheck shell=bash disable=SC2154
#
# Double-confirms. Loops state_list_realms calling the per-realm
# uninstall logic (inlined to avoid re-sourcing the flow in a loop).
# Then removes the /etc/systemd/system/mangos-*.service files, asks
# whether to also remove the mangos user + home (which deletes backups),
# and removes /etc/mangos-installer/secrets.env.
#
# We do NOT apt-remove the dependency packages — they may be used
# elsewhere. The closing banner lists what was left behind.

ui_print_banner "mangos installer ${INSTALLER_VERSION} — uninstall EVERYTHING"

config_load

_uninstall_all_confirm() {
  if [[ "${MANGOS_CONFIRM_UNINSTALL_ALL:-}" == "yes" ]]; then
    ui_status_warn "--yes: skipping typed confirmation"
    return 0
  fi
  ui_status_warn "this removes every realm, every database mangos owns, and the"
  ui_status_warn "systemd units. it will ask separately before deleting the"
  ui_status_warn "mangos user + home (which holds your DB backups)."
  ui_status_info ""
  local typed
  while :; do
    read -rp "type 'YES' (uppercase) to confirm: " typed
    [[ "$typed" == "YES" ]] && break
    ui_status_warn "not confirmed. Ctrl-C to abort, or type YES to proceed."
  done
}

_uninstall_all_realms() {
  local realms r
  realms=$(state_list_realms)
  [[ -z "$realms" ]] && { ui_status_info "no realms to remove"; return 0; }

  # Use the single-realm uninstall flow in a subshell so its traps and
  # state don't leak back. Each subshell re-sources config, so ordering
  # is fine even as the config file gets updated.
  while IFS= read -r r; do
    [[ -z "$r" ]] && continue
    ui_status_info ""
    ui_status_info "--- uninstalling realm '$r' ---"
    (
      export MANGOS_UNINSTALL_REALM="$r"
      export MANGOS_CONFIRM_UNINSTALL="yes"
      # shellcheck disable=SC1090
      . "$MANGOS_INSTALLER_DIR/flows/uninstall-realm.sh"
    )
  done <<< "$realms"
}

_uninstall_all_remove_units() {
  local changed=0 f
  if systemd_have; then
    for f in /etc/systemd/system/mangos-realmd.service /etc/systemd/system/mangos-mangosd@.service; do
      if [[ -f "$f" ]]; then
        rm -f -- "$f"
        changed=1
        ui_status_ok "removed $f"
      fi
    done
    (( changed )) && systemctl daemon-reload
  else
    log_warn "no systemd; nothing to unregister"
  fi
}

_uninstall_all_remove_secrets() {
  if [[ -f "$MANGOS_SECRETS_FILE" ]]; then
    rm -f -- "$MANGOS_SECRETS_FILE"
    ui_status_ok "removed $MANGOS_SECRETS_FILE"
  fi
  if [[ -d "$MANGOS_SECRETS_DIR" ]]; then
    rmdir -- "$MANGOS_SECRETS_DIR" 2>/dev/null || true
  fi
}

_uninstall_all_prompt_user_removal() {
  local user="${MANGOS_USER:-$MANGOS_DEFAULT_USER}"
  if ! id -u "$user" >/dev/null 2>&1; then
    return 0
  fi
  ui_status_warn ""
  ui_status_warn "the mangos user '$user' still exists."
  ui_status_warn "its home is $MANGOS_ROOT's parent and contains your DB backups."
  if ui_prompt_yes_no "also remove the mangos user and home? this DELETES backups." \
                      "no" "MANGOS_REMOVE_USER"; then
    systemctl stop "mangos-realmd.service" 2>/dev/null || true
    if userdel -r "$user" >>"$MANGOS_LOG_FILE" 2>&1; then
      ui_status_ok "user '$user' and home directory removed"
    else
      log_warn "userdel failed; the mangos user and its home are still present"
    fi
  else
    ui_status_info "keeping mangos user and home (backups preserved at $MANGOS_ROOT/<realm>/backups/)"
  fi
}

# ---------------------------------------------------------------------------

_uninstall_all_confirm
_uninstall_all_realms
_uninstall_all_remove_units
_uninstall_all_remove_secrets
_uninstall_all_prompt_user_removal

ui_print_banner "uninstall complete"
ui_status_info "apt packages (cmake, mariadb-server, etc.) were NOT removed;"
ui_status_info "they may be used by other software on this host. remove manually"
ui_status_info "with 'apt-get remove' if you know they are no longer needed."
ui_status_info "installer log: $MANGOS_LOG_FILE"
