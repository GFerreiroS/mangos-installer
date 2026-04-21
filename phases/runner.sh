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

# Re-attach stdin to /dev/tty so interactive prompts work when the bootstrap
# was piped (curl | bash). Safe here because runner.sh is read from a file,
# not from stdin, so replacing fd 0 does not affect script reading.
if [[ ! -t 0 ]] && [[ -e /dev/tty ]] && [[ -r /dev/tty ]]; then
  exec </dev/tty
fi

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

# If a previous install's config.env exists at the final install root,
# prefer that (re-run detection). Otherwise use the bootstrap staging
# location; phase 1 migrates it into the final location on first install.
MANGOS_FINAL_CONFIG="$MANGOS_DEFAULT_INSTALL_ROOT/.installer/config.env"
MANGOS_FINAL_STATE_DIR="$MANGOS_DEFAULT_INSTALL_ROOT/.installer/state"
if [[ -z "${MANGOS_CONFIG_FILE:-}" ]]; then
  if [[ -f "$MANGOS_FINAL_CONFIG" ]]; then
    MANGOS_CONFIG_FILE="$MANGOS_FINAL_CONFIG"
    MANGOS_STATE_FILE="${MANGOS_STATE_FILE:-$MANGOS_FINAL_STATE_DIR/global.state}"
  else
    MANGOS_CONFIG_FILE="$MANGOS_BOOTSTRAP_STAGING/config.env"
    MANGOS_STATE_FILE="${MANGOS_STATE_FILE:-$MANGOS_BOOTSTRAP_STAGING/state/global.state}"
  fi
fi
MANGOS_SECRETS_FILE="${MANGOS_SECRETS_FILE:-$MANGOS_SECRETS_DIR/secrets.env}"
mkdir -p -- "$(dirname -- "$MANGOS_STATE_FILE")"
export MANGOS_CONFIG_FILE MANGOS_SECRETS_FILE MANGOS_STATE_FILE

# Reload prior config so re-runs can read previous answers.
config_load

# state.json schema compatibility. Current in-code schema is 1. If a
# previous install wrote a higher schema_version, a newer installer was
# used and we must not clobber its state blindly.
_runner_check_state_schema() {
  local sj="$MANGOS_DEFAULT_INSTALL_ROOT/.installer/state.json"
  [[ -f "$sj" ]] || return 0
  local existing
  existing=$(sed -nE 's/.*"schema_version": *([0-9]+).*/\1/p' "$sj" | head -n 1)
  [[ -z "$existing" ]] && return 0
  if (( existing > 1 )); then
    die "existing state.json has schema_version=$existing but this installer only understands 1
    a newer installer was used against this host. upgrade this installer or run it on a fresh host.
    state.json path: $sj"
  fi
  # Lower schema_versions are forward-compatible; state_json_write rewrites
  # the file with the current schema on every phase.
}
_runner_check_state_schema

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

# Pick a default flow: menu if an install already exists, fresh-install
# otherwise. Explicit --flow= (propagated via MANGOS_FLOW) wins.
if [[ -z "${MANGOS_FLOW:-}" ]]; then
  if [[ -f "$MANGOS_FINAL_CONFIG" ]]; then
    MANGOS_FLOW="menu"
  else
    MANGOS_FLOW="fresh-install"
  fi
fi
export MANGOS_ROOT="${MANGOS_ROOT:-$MANGOS_DEFAULT_INSTALL_ROOT}"

log_info "runner started; flow=${MANGOS_FLOW} dev_mode=${MANGOS_DEV_MODE:-0} non_interactive=${MANGOS_NONINTERACTIVE:-0}"

case "${MANGOS_FLOW}" in
  menu)
    # shellcheck source=../flows/menu.sh
    . "$MANGOS_INSTALLER_DIR/flows/menu.sh" ;;
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
