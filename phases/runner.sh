#!/usr/bin/env bash
# mangos-installer — phase dispatcher (sourced libraries, dispatches flows)
# SPDX-License-Identifier: GPL-2.0-only
# See CLAUDE.md for design, README.md for usage
# shellcheck disable=SC2154
#
# Invoked by install.sh after the installer is located/fetched. Expects
# MANGOS_INSTALLER_DIR, MANGOS_BOOT_LOG_FILE, MANGOS_FLOW (and optional
# MANGOS_NONINTERACTIVE, MANGOS_DEV_MODE, MANGOS_TMPDIR_TO_CLEANUP) in env.
set -euo pipefail
IFS=$'\n\t'

MANGOS_INSTALLER_DIR="${MANGOS_INSTALLER_DIR:-$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)}"
export MANGOS_INSTALLER_DIR

# --- Source libraries in dependency order ---
# shellcheck source=../lib/constants.sh
. "$MANGOS_INSTALLER_DIR/lib/constants.sh"
# shellcheck source=../lib/log.sh
. "$MANGOS_INSTALLER_DIR/lib/log.sh"
# shellcheck source=../lib/ui.sh
. "$MANGOS_INSTALLER_DIR/lib/ui.sh"
# shellcheck source=../lib/platform.sh
. "$MANGOS_INSTALLER_DIR/lib/platform.sh"
# shellcheck source=../lib/privilege.sh
. "$MANGOS_INSTALLER_DIR/lib/privilege.sh"
# shellcheck source=../lib/state.sh
. "$MANGOS_INSTALLER_DIR/lib/state.sh"
# shellcheck source=../lib/config.sh
. "$MANGOS_INSTALLER_DIR/lib/config.sh"
# shellcheck source=../lib/secrets.sh
. "$MANGOS_INSTALLER_DIR/lib/secrets.sh"
# shellcheck source=../lib/download.sh
. "$MANGOS_INSTALLER_DIR/lib/download.sh"
# shellcheck source=../lib/archive.sh
. "$MANGOS_INSTALLER_DIR/lib/archive.sh"
# shellcheck source=../lib/gamedata.sh
. "$MANGOS_INSTALLER_DIR/lib/gamedata.sh"
# shellcheck source=../lib/db.sh
. "$MANGOS_INSTALLER_DIR/lib/db.sh"
# shellcheck source=../lib/systemd.sh
. "$MANGOS_INSTALLER_DIR/lib/systemd.sh"
# shellcheck source=../lib/cores.sh
. "$MANGOS_INSTALLER_DIR/lib/cores.sh"

# --- Logging ---
# Continue writing to the bootstrap log; phase 1 (milestone 2) will migrate
# everything under ~mangos/mangos/.installer/logs/ once the install root exists.
MANGOS_LOG_FILE="${MANGOS_BOOT_LOG_FILE:-/tmp/mangos-installer-runner-$$.log}"
export MANGOS_LOG_FILE

# --- Bootstrap staging dir (config + state until phase 1 moves them) ---
mkdir -p -- "$MANGOS_BOOTSTRAP_STAGING"
chmod 0700 -- "$MANGOS_BOOTSTRAP_STAGING" 2>/dev/null || true

MANGOS_CONFIG_FILE="${MANGOS_CONFIG_FILE:-$MANGOS_BOOTSTRAP_STAGING/config.env}"
MANGOS_SECRETS_FILE="${MANGOS_SECRETS_FILE:-$MANGOS_SECRETS_DIR/secrets.env}"
MANGOS_STATE_FILE="${MANGOS_STATE_FILE:-$MANGOS_BOOTSTRAP_STAGING/state/global.state}"
mkdir -p -- "$(dirname -- "$MANGOS_STATE_FILE")"
export MANGOS_CONFIG_FILE MANGOS_SECRETS_FILE MANGOS_STATE_FILE

# Reload prior config so re-runs can read previous answers.
config_load

# Re-hydrate MANGOS_REALM_* from REALM_<name>_* if a realm is already on file.
# Lets phases past 0 address realm values by stable names even when phase 0
# short-circuits on re-run.
if [[ -n "${MANGOS_CURRENT_REALM:-}" ]]; then
  config_hydrate_realm "$MANGOS_CURRENT_REALM"
fi

# Bootstrap couldn't clean its tmpdir (it exec'd this process); take over.
if [[ -n "${MANGOS_TMPDIR_TO_CLEANUP:-}" ]]; then
  trap 'rm -rf -- "$MANGOS_TMPDIR_TO_CLEANUP"' EXIT
fi

log_info "runner started; flow=${MANGOS_FLOW:-fresh-install} dev_mode=${MANGOS_DEV_MODE:-0} non_interactive=${MANGOS_NONINTERACTIVE:-0}"

case "${MANGOS_FLOW:-fresh-install}" in
  fresh-install)
    # shellcheck source=../flows/fresh-install.sh
    . "$MANGOS_INSTALLER_DIR/flows/fresh-install.sh" ;;
  add-realm)
    # shellcheck source=../flows/add-realm.sh
    . "$MANGOS_INSTALLER_DIR/flows/add-realm.sh" ;;
  update-realm)
    # shellcheck source=../flows/update-realm.sh
    . "$MANGOS_INSTALLER_DIR/flows/update-realm.sh" ;;
  uninstall-realm)
    # shellcheck source=../flows/uninstall-realm.sh
    . "$MANGOS_INSTALLER_DIR/flows/uninstall-realm.sh" ;;
  uninstall-all)
    # shellcheck source=../flows/uninstall-all.sh
    . "$MANGOS_INSTALLER_DIR/flows/uninstall-all.sh" ;;
  resume)
    # shellcheck source=../flows/resume.sh
    . "$MANGOS_INSTALLER_DIR/flows/resume.sh" ;;
  *) die "unknown flow: ${MANGOS_FLOW}" ;;
esac
