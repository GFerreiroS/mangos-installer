#!/usr/bin/env bash
# mangos-installer — bootstrap entrypoint
# SPDX-License-Identifier: GPL-2.0-only
# See CLAUDE.md for design, README.md for usage
#
# This script is small and self-contained. It does the cheap sanity work
# (root, bash, curl, tar, OS, arch), re-attaches stdin to /dev/tty when
# piped through `curl ... | sudo bash`, fetches the installer tarball
# from GitHub (or uses a local checkout with --dev-mode), and execs into
# phases/runner.sh which loads the libraries and dispatches the flow.
set -euo pipefail
IFS=$'\n\t'

# --- Inline constants (small subset; lib/constants.sh is sourced by the runner) ---
INSTALLER_REPO_URL="https://github.com/GFerreiroS/mangos-installer"
INSTALLER_TARBALL_URL="https://github.com/GFerreiroS/mangos-installer/archive/refs/tags"
INSTALLER_TARBALL_MAIN="https://github.com/GFerreiroS/mangos-installer/archive/refs/heads/main.tar.gz"
INSTALLER_VERSION="1.0.0"
MIN_BASH_MAJOR=5
MIN_BASH_MINOR=0

# --- Boot log (real logging starts after the runner sources lib/log.sh) ---
BOOT_LOG_FILE="/tmp/mangos-installer-$$-boot.log"
: > "$BOOT_LOG_FILE" 2>/dev/null || true

_boot_log() {
  local level="$1"; shift
  printf '%s [%s] [bootstrap] %s\n' \
    "$(date -u +'%Y-%m-%d %H:%M:%S')" "$level" "$*" >> "$BOOT_LOG_FILE" 2>/dev/null || true
}
boot_info()  { _boot_log INFO  "$*"; printf '%s\n' "$*" >&2; }
boot_warn()  { _boot_log WARN  "$*"; printf '[!] %s\n' "$*" >&2; }
boot_error() { _boot_log ERROR "$*"; printf '[FAIL] %s\n' "$*" >&2; }
boot_die()   { boot_error "$*"; printf '\nbootstrap log: %s\n' "$BOOT_LOG_FILE" >&2; exit 1; }

# --- Argument parsing ---
DEV_MODE=0
NON_INTERACTIVE_FLAG="${MANGOS_NONINTERACTIVE:-0}"
INSTALLER_FLOW="${MANGOS_FLOW:-}"   # empty = let the runner auto-detect

# Map a --key=value (or --key value) CLI flag to a MANGOS_* env var. Keeps
# the interactive prompts (which already read MANGOS_*) and the flag-driven
# mode from drifting apart.
_set_env() {
  local name="$1" val="$2"
  printf -v "$name" '%s' "$val"
  export "$name"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dev-mode)         DEV_MODE=1; shift ;;
    --non-interactive)  NON_INTERACTIVE_FLAG=1; shift ;;
    --flow=*)           INSTALLER_FLOW="${1#*=}"; shift ;;

    # --- realm identity ----------------------------------------------------
    --core=*)               _set_env MANGOS_REALM_CORE       "${1#*=}"; shift ;;
    --realm-name=*)         _set_env MANGOS_REALM_NAME       "${1#*=}"; shift ;;
    --realm-display-name=*) _set_env MANGOS_REALM_DISPLAY    "${1#*=}"; shift ;;
    --realm-address=*)      _set_env MANGOS_REALM_ADDRESS    "${1#*=}"; shift ;;
    --realm-world-port=*)   _set_env MANGOS_REALM_WORLD_PORT "${1#*=}"; shift ;;

    # --- database ---------------------------------------------------------
    --db-mode=*)            _set_env MANGOS_DB_MODE           "${1#*=}"; shift ;;
    --db-host=*)            _set_env MANGOS_DB_HOST           "${1#*=}"; shift ;;
    --db-port=*)            _set_env MANGOS_DB_PORT           "${1#*=}"; shift ;;
    --db-admin-user=*)      _set_env MANGOS_DB_ADMIN_USER     "${1#*=}"; shift ;;
    --db-admin-password=*)  _set_env MANGOS_DB_ADMIN_PASSWORD "${1#*=}"; shift ;;

    # --- gamedata ---------------------------------------------------------
    --gamedata-source=*)    _set_env MANGOS_GAMEDATA_SOURCE "${1#*=}"; shift ;;
    --gamedata-path=*)      _set_env MANGOS_GAMEDATA_PATH   "${1#*=}"; shift ;;
    --gamedata-url=*)       _set_env MANGOS_GAMEDATA_URL    "${1#*=}"; shift ;;

    # --- confirmation shortcuts ------------------------------------------
    --yes|-y)
      _set_env MANGOS_ALLOW_INSECURE_URL   "yes"
      _set_env MANGOS_CONFIRM_UNINSTALL    "yes"
      _set_env MANGOS_CONFIRM_UNINSTALL_ALL "yes"
      shift ;;
    --force-unsupported) _set_env MANGOS_FORCE_UNSUPPORTED yes; shift ;;

    --version|-V) printf 'mangos-installer %s\n' "$INSTALLER_VERSION"; exit 0 ;;
    --help|-h)
      cat <<EOF
mangos-installer ${INSTALLER_VERSION}

Usage:
  curl -fsSL ${INSTALLER_REPO_URL}/raw/main/install.sh | sudo bash
  sudo bash install.sh [options]

Invocation options:
  --dev-mode           Use the local checkout instead of fetching from GitHub
  --non-interactive    Require every answer to come from CLI flags or env vars
  --flow=<name>        fresh-install | menu | add-realm | update-realm |
                       uninstall-realm | uninstall-all | resume
                       (default: auto-detect — menu if an install already
                       exists, fresh-install otherwise)

Realm identity (fresh install / add realm):
  --core=zero                     MaNGOS core (zero|one|two|three)
  --realm-name=<id>               internal lowercase id, e.g. "zero"
  --realm-display-name=<str>      display name shown in the client
  --realm-address=<host-or-ip>    address the client connects to
  --realm-world-port=<n>          world server port (default 8085)

Database:
  --db-mode=local|remote
  --db-host=<host>                remote mode: DB host
  --db-port=<n>                   remote mode: DB port
  --db-admin-user=<user>          DB admin user
  --db-admin-password=<pw>        DB admin password (avoid on shared hosts; env var preferred)

Gamedata:
  --gamedata-source=path|url|manual
  --gamedata-path=<abs-path>      client path (source=path)
  --gamedata-url=<url>            client archive URL (source=url)

Confirmation:
  --yes, -y            Pre-accept prompts (insecure URL, uninstall, etc.)
  --force-unsupported  Run on an OS that the installer normally rejects

Misc:
  --version, -V        Print version and exit
  --help, -h           This message

All flags have equivalent MANGOS_* environment variables — see CLAUDE.md.
Documentation: ${INSTALLER_REPO_URL}
EOF
      exit 0 ;;
    *) boot_die "unknown argument: $1 (try --help)" ;;
  esac
done

_boot_log INFO "mangos-installer ${INSTALLER_VERSION} bootstrap starting (pid=$$)"

# --- Sanity checks ---
[[ $EUID -eq 0 ]] || boot_die "this installer must be run as root (try: sudo bash install.sh)"

if (( BASH_VERSINFO[0] < MIN_BASH_MAJOR )) \
   || { (( BASH_VERSINFO[0] == MIN_BASH_MAJOR )) && (( BASH_VERSINFO[1] < MIN_BASH_MINOR )); }; then
  boot_die "bash ${MIN_BASH_MAJOR}.${MIN_BASH_MINOR}+ required (have ${BASH_VERSINFO[0]}.${BASH_VERSINFO[1]})"
fi

for cmd in curl tar; do
  command -v "$cmd" >/dev/null 2>&1 || boot_die "required command not found: $cmd"
done
boot_info "[OK] sanity (root, bash ${BASH_VERSINFO[0]}.${BASH_VERSINFO[1]}, curl, tar)"

# --- Re-attach stdin to /dev/tty if piped, so prompts work ---
if [[ ! -t 0 ]] && [[ -e /dev/tty ]] && [[ -r /dev/tty ]]; then
  exec </dev/tty
  _boot_log INFO "re-attached stdin from /dev/tty"
fi

# --- Quick OS/arch sanity (libs not loaded yet) ---
if [[ ! -f /etc/os-release ]]; then
  boot_die "cannot detect OS: /etc/os-release missing"
fi
# shellcheck source=/dev/null
. /etc/os-release
case "${ID:-}:${VERSION_ID:-}" in
  ubuntu:22.04|ubuntu:24.04|debian:12)
    boot_info "[OK] OS: ${ID} ${VERSION_ID}" ;;
  ubuntu:*|debian:*)
    boot_warn "OS: ${ID} ${VERSION_ID} (not in supported list; phase 0 will re-check)" ;;
  *)
    boot_die "OS '${ID:-unknown}' is not supported (need ubuntu:22.04, ubuntu:24.04, or debian:12)" ;;
esac

ARCH="$(uname -m)"
case "$ARCH" in
  x86_64|aarch64) boot_info "[OK] arch: $ARCH" ;;
  *) boot_die "architecture '$ARCH' is not supported (need x86_64 or aarch64)" ;;
esac

# --- Locate or fetch installer ---
INSTALLER_DIR=""
TMPDIR_RUN=""

if [[ "$DEV_MODE" -eq 1 ]]; then
  if [[ -n "${BASH_SOURCE[0]:-}" ]] && [[ -f "${BASH_SOURCE[0]}" ]]; then
    INSTALLER_DIR=$(cd -- "$(dirname -- "$(readlink -f -- "${BASH_SOURCE[0]}")")" && pwd)
    boot_info "dev-mode: using local installer at $INSTALLER_DIR"
  else
    boot_die "--dev-mode set but cannot resolve script path (BASH_SOURCE empty; piped?)"
  fi
fi

if [[ -z "$INSTALLER_DIR" ]]; then
  TMPDIR_RUN="/tmp/mangos-installer-$$"
  mkdir -p -- "$TMPDIR_RUN"
  trap 'rm -rf -- "$TMPDIR_RUN"' EXIT

  TARBALL_PATH="$TMPDIR_RUN/installer.tar.gz"
  fetched=0
  for url in \
      "${INSTALLER_TARBALL_URL}/v${INSTALLER_VERSION}.tar.gz" \
      "$INSTALLER_TARBALL_MAIN"; do
    boot_info "fetching: $url"
    if curl -fL --progress-bar --retry 3 --retry-delay 5 --max-time 120 --connect-timeout 15 \
         -o "$TARBALL_PATH" -- "$url"; then
      fetched=1
      _boot_log INFO "fetched ok: $url"
      break
    else
      boot_warn "fetch failed; trying next source"
    fi
  done
  [[ $fetched -eq 1 ]] || boot_die "all tarball sources failed; see $BOOT_LOG_FILE"

  if ! tar -xzf "$TARBALL_PATH" -C "$TMPDIR_RUN" 2>>"$BOOT_LOG_FILE"; then
    boot_die "tarball extraction failed; see $BOOT_LOG_FILE"
  fi

  INSTALLER_DIR=$(find "$TMPDIR_RUN" -mindepth 1 -maxdepth 1 -type d -name 'mangos-installer-*' | head -n 1)
  [[ -d "$INSTALLER_DIR" ]] || boot_die "cannot find extracted installer dir under $TMPDIR_RUN"
  boot_info "extracted to $INSTALLER_DIR"

  # exec replaces this process; clear the trap and let the runner set its own
  trap - EXIT
fi

[[ -f "$INSTALLER_DIR/phases/runner.sh" ]] \
  || boot_die "runner not found: $INSTALLER_DIR/phases/runner.sh"

export MANGOS_INSTALLER_DIR="$INSTALLER_DIR"
export MANGOS_BOOT_LOG_FILE="$BOOT_LOG_FILE"
export MANGOS_FLOW="$INSTALLER_FLOW"
export MANGOS_NONINTERACTIVE="$NON_INTERACTIVE_FLAG"
export MANGOS_DEV_MODE="$DEV_MODE"
[[ -n "$TMPDIR_RUN" ]] && export MANGOS_TMPDIR_TO_CLEANUP="$TMPDIR_RUN"

_boot_log INFO "handing off to runner.sh (flow=$INSTALLER_FLOW non_interactive=$NON_INTERACTIVE_FLAG dev_mode=$DEV_MODE)"
exec bash "$INSTALLER_DIR/phases/runner.sh"
