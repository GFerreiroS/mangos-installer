#!/usr/bin/env bash
# mangos-installer — phase 00: preflight system checks + interactive configuration
# SPDX-License-Identifier: GPL-2.0-only
# See CLAUDE.md for design, README.md for usage
# shellcheck disable=SC2154
#
# The only always-interactive phase. Runs system checks, collects realm
# identity, database mode, and gamedata source, then persists the answers
# to config.env (mangos-readable) and /etc/mangos-installer/secrets.env
# (root-only). If a gamedata URL was provided, kicks off a background
# download that phase 11 will wait on.

run_phase_00() {
  MANGOS_CURRENT_PHASE="phase-00-preflight"
  ui_phase_header 0 14 "preflight"

  if state_has_completed "$MANGOS_CURRENT_PHASE"; then
    ui_status_ok "preflight already complete; reusing previous answers"
    config_load
    return 0
  fi

  _preflight_system_checks
  _preflight_prompt_realm
  _preflight_prompt_db
  _preflight_prompt_gamedata
  _preflight_persist_answers

  state_mark_complete "$MANGOS_CURRENT_PHASE"
  ui_status_ok "preflight complete"
}

# --- system checks -----------------------------------------------------------

_preflight_system_checks() {
  privilege_require_root

  platform_detect_os
  platform_detect_arch

  if ! platform_arch_supported; then
    die "unsupported architecture: ${MANGOS_ARCH} (need: ${SUPPORTED_ARCHS[*]})"
  fi
  ui_status_ok "architecture: ${MANGOS_ARCH}"

  local os_status=0
  platform_check_supported || os_status=$?
  case "$os_status" in
    0) ui_status_ok "OS: ${MANGOS_OS_ID} ${MANGOS_OS_VERSION}" ;;
    1) ui_status_warn "OS ${MANGOS_OS_ID} ${MANGOS_OS_VERSION} is untested but may work"
       if ! ui_prompt_yes_no "continue anyway?" "no" "MANGOS_FORCE_UNSUPPORTED"; then
         die "aborted by user"
       fi ;;
    2) die "unsupported OS: ${MANGOS_OS_ID} ${MANGOS_OS_VERSION} (need: ${SUPPORTED_DISTROS[*]})" ;;
  esac

  local ram_gb
  ram_gb=$(platform_ram_gb)
  if [[ "${ram_gb:-0}" -lt 2 ]]; then
    ui_status_warn "RAM: ${ram_gb}GB (build phase will be slow; 4GB+ recommended)"
  else
    ui_status_ok "RAM: ${ram_gb}GB"
  fi

  local disk_gb
  disk_gb=$(platform_disk_gb /home)
  if [[ "${disk_gb:-0}" -lt 10 ]]; then
    die "insufficient disk at /home: ${disk_gb}GB free (need >= 10GB; 30GB+ recommended)"
  fi
  ui_status_ok "disk free at /home: ${disk_gb}GB"

  if curl -fsSL --max-time 10 --head https://github.com >/dev/null 2>&1; then
    ui_status_ok "network: GitHub reachable"
  else
    die "network check failed: cannot reach https://github.com
    - check DNS: cat /etc/resolv.conf
    - check proxy:    echo \$http_proxy \$https_proxy
    - check firewall: the installer needs outbound 443 to github.com and openssl.org"
  fi
}

# --- realm prompts -----------------------------------------------------------

_preflight_prompt_realm() {
  ui_status_info "realm configuration"

  local core
  core=$(ui_prompt_choice "MaNGOS core" "zero" "MANGOS_REALM_CORE" zero one two three)
  if ! core_supported "$core"; then
    die "core '$core' is not yet implemented
    $(core_describe "$core")
    see lib/cores.sh for the porting checklist; contributions welcome"
  fi
  MANGOS_REALM_CORE="$core"

  local realm_name
  realm_name=$(ui_prompt_text "realm internal name (lowercase identifier)" "zero" "MANGOS_REALM_NAME")
  if [[ ! "$realm_name" =~ ^[a-z][a-z0-9_]{0,31}$ ]]; then
    die "invalid realm name '$realm_name' (need [a-z][a-z0-9_]{0,31})"
  fi
  MANGOS_REALM_NAME="$realm_name"

  MANGOS_REALM_DISPLAY=$(ui_prompt_text "realm display name (shown in client)" "My Vanilla Realm" "MANGOS_REALM_DISPLAY")

  local default_addr
  default_addr=$(ip route get 1.1.1.1 2>/dev/null | awk '{ for (i=1;i<=NF;i++) if ($i=="src") { print $(i+1); exit } }') || true
  default_addr="${default_addr:-127.0.0.1}"
  MANGOS_REALM_ADDRESS=$(ui_prompt_text "realm address (IP/hostname clients connect to)" "$default_addr" "MANGOS_REALM_ADDRESS")

  MANGOS_REALM_WORLD_PORT=$(ui_prompt_text "world server port" "8085" "MANGOS_REALM_WORLD_PORT")
  if [[ ! "$MANGOS_REALM_WORLD_PORT" =~ ^[0-9]+$ ]]; then
    die "invalid world port '$MANGOS_REALM_WORLD_PORT' (need integer)"
  fi
  if (( MANGOS_REALM_WORLD_PORT < 1024 )) || (( MANGOS_REALM_WORLD_PORT > 65535 )); then
    die "world port '$MANGOS_REALM_WORLD_PORT' out of range (1024-65535)"
  fi
  # Pre-check: warn if auth port 3724 or the chosen world port is already
  # bound. Phase 14 would catch this later but the error is clearer now.
  if port_in_use 3724; then
    ui_status_warn "port 3724 (auth) is already in use on this host"
    ui_status_warn "  sudo ss -lntp sport = :3724   # to see what owns it"
    if ! ui_prompt_yes_no "continue anyway? (phase 14 will fail if it stays bound)" \
                          "no" "MANGOS_ALLOW_PORT_COLLISION"; then
      die "aborted due to port 3724 collision"
    fi
  fi
  if port_in_use "$MANGOS_REALM_WORLD_PORT"; then
    ui_status_warn "world port $MANGOS_REALM_WORLD_PORT is already in use"
    if ! ui_prompt_yes_no "continue anyway? (phase 14 will fail if it stays bound)" \
                          "no" "MANGOS_ALLOW_PORT_COLLISION"; then
      die "aborted due to port $MANGOS_REALM_WORLD_PORT collision"
    fi
  fi

  export MANGOS_REALM_CORE MANGOS_REALM_NAME MANGOS_REALM_DISPLAY MANGOS_REALM_ADDRESS MANGOS_REALM_WORLD_PORT
}

# --- DB prompts --------------------------------------------------------------

_preflight_prompt_db() {
  ui_status_info "database configuration"

  MANGOS_DB_MODE=$(ui_prompt_choice "database mode" "local" "MANGOS_DB_MODE" local remote)

  if [[ "$MANGOS_DB_MODE" == "local" ]]; then
    MANGOS_DB_HOST="localhost"
    MANGOS_DB_PORT="3306"
    MANGOS_DB_ADMIN_USER=$(ui_prompt_text "MariaDB admin user to create" "mangos" "MANGOS_DB_ADMIN_USER")
    if [[ "${MANGOS_NONINTERACTIVE:-0}" == "1" ]] && [[ -n "${MANGOS_DB_ADMIN_PASSWORD:-}" ]]; then
      : # caller supplied password non-interactively; use it
    else
      MANGOS_DB_ADMIN_PASSWORD=$(_generate_password 24)
      ui_status_info "generated MariaDB password for '${MANGOS_DB_ADMIN_USER}':"
      if _ui_use_color; then
        printf '\n      \033[1m%s\033[0m\n\n' "$MANGOS_DB_ADMIN_PASSWORD" >&2
      else
        printf '\n      %s\n\n' "$MANGOS_DB_ADMIN_PASSWORD" >&2
      fi
      ui_status_warn "save this password now — it is also written to ${MANGOS_SECRETS_FILE}"
    fi
  else
    MANGOS_DB_HOST=$(ui_prompt_text "remote DB host" "localhost" "MANGOS_DB_HOST")
    MANGOS_DB_PORT=$(ui_prompt_text "remote DB port" "3306" "MANGOS_DB_PORT")
    MANGOS_DB_ADMIN_USER=$(ui_prompt_text "remote DB admin user" "mangos" "MANGOS_DB_ADMIN_USER")
    MANGOS_DB_ADMIN_PASSWORD=$(ui_prompt_password "remote DB admin password" "MANGOS_DB_ADMIN_PASSWORD")
  fi

  export MANGOS_DB_MODE MANGOS_DB_HOST MANGOS_DB_PORT MANGOS_DB_ADMIN_USER MANGOS_DB_ADMIN_PASSWORD
}

# --- gamedata prompt ---------------------------------------------------------

_preflight_prompt_gamedata() {
  ui_status_info "gamedata source"
  ui_status_info "the WoW 1.12.x client (~6GB) is required for extraction in phase 12."
  ui_status_info "you must own a legitimate copy. the installer does not distribute Blizzard data."

  MANGOS_GAMEDATA_SOURCE=$(ui_prompt_choice "gamedata source" "manual" "MANGOS_GAMEDATA_SOURCE" path url manual)

  case "$MANGOS_GAMEDATA_SOURCE" in
    path)
      MANGOS_GAMEDATA_PATH=$(ui_prompt_text "absolute path to WoW client directory" "/srv/wow-1.12.3" "MANGOS_GAMEDATA_PATH")
      if ! gamedata_validate_structure "$MANGOS_GAMEDATA_PATH" "$MANGOS_REALM_CORE"; then
        die "gamedata at '$MANGOS_GAMEDATA_PATH' failed validation"
      fi
      ui_status_ok "gamedata path accepted (structural validation lands in milestone 3)"
      ;;
    url)
      MANGOS_GAMEDATA_URL=$(ui_prompt_text "URL to gamedata archive (https/sftp recommended)" "" "MANGOS_GAMEDATA_URL")
      [[ -z "$MANGOS_GAMEDATA_URL" ]] && die "gamedata URL cannot be empty"
      local proto_status=0
      download_validate_protocol "$MANGOS_GAMEDATA_URL" || proto_status=$?
      case "$proto_status" in
        0) ui_status_ok "URL protocol OK (secure)" ;;
        1) ui_status_warn "URL uses an insecure protocol (http/ftp). traffic may be intercepted."
           if ! ui_prompt_yes_no "continue with insecure URL?" "no" "MANGOS_ALLOW_INSECURE_URL"; then
             die "aborted by user"
           fi ;;
        *) die "unsupported URL protocol in '$MANGOS_GAMEDATA_URL'" ;;
      esac
      local dl_dir="$MANGOS_BOOTSTRAP_STAGING/downloads"
      mkdir -p -- "$dl_dir"
      MANGOS_GAMEDATA_DOWNLOAD_DEST="$dl_dir/gamedata.archive"
      MANGOS_GAMEDATA_DOWNLOAD_PIDFILE="$dl_dir/gamedata.pid"
      ui_status_info "starting background download (continues in parallel with later phases)..."
      download_background "$MANGOS_GAMEDATA_URL" "$MANGOS_GAMEDATA_DOWNLOAD_DEST" "$MANGOS_GAMEDATA_DOWNLOAD_PIDFILE"
      local bg_pid
      bg_pid=$(cat -- "$MANGOS_GAMEDATA_DOWNLOAD_PIDFILE")
      ui_status_ok "background download running (pid ${bg_pid}); phase 11 will wait on it"
      ;;
    manual)
      ui_status_info "phase 11 will stop and instruct you where to place the client files manually."
      ;;
  esac

  export MANGOS_GAMEDATA_SOURCE
  [[ -n "${MANGOS_GAMEDATA_PATH:-}" ]]               && export MANGOS_GAMEDATA_PATH
  [[ -n "${MANGOS_GAMEDATA_URL:-}" ]]                && export MANGOS_GAMEDATA_URL
  [[ -n "${MANGOS_GAMEDATA_DOWNLOAD_DEST:-}" ]]      && export MANGOS_GAMEDATA_DOWNLOAD_DEST
  [[ -n "${MANGOS_GAMEDATA_DOWNLOAD_PIDFILE:-}" ]]   && export MANGOS_GAMEDATA_DOWNLOAD_PIDFILE
}

# --- persist answers ---------------------------------------------------------

_preflight_persist_answers() {
  ui_status_info "writing config and secrets..."

  mkdir -p -- "$(dirname -- "$MANGOS_CONFIG_FILE")"
  secrets_init

  config_set INSTALLER_VERSION "$INSTALLER_VERSION"
  config_set INSTALLER_SCHEMA  "1"
  config_set MANGOS_USER       "$MANGOS_DEFAULT_USER"
  config_set MANGOS_ROOT       "$MANGOS_DEFAULT_INSTALL_ROOT"
  config_set OPENSSL_PREFIX    "${MANGOS_DEFAULT_INSTALL_ROOT}/opt/openssl-1.1"

  config_set DB_MODE        "$MANGOS_DB_MODE"
  config_set DB_HOST        "$MANGOS_DB_HOST"
  config_set DB_PORT        "$MANGOS_DB_PORT"
  config_set DB_ADMIN_USER  "$MANGOS_DB_ADMIN_USER"

  # Pointer so re-runs / phases past 0 know which realm is "current".
  config_set MANGOS_CURRENT_REALM "$MANGOS_REALM_NAME"

  config_set GAMEDATA_SOURCE "$MANGOS_GAMEDATA_SOURCE"
  [[ -n "${MANGOS_GAMEDATA_PATH:-}" ]]               && config_set GAMEDATA_PATH              "$MANGOS_GAMEDATA_PATH"
  [[ -n "${MANGOS_GAMEDATA_URL:-}" ]]                && config_set GAMEDATA_URL               "$MANGOS_GAMEDATA_URL"
  [[ -n "${MANGOS_GAMEDATA_DOWNLOAD_DEST:-}" ]]      && config_set GAMEDATA_DOWNLOAD_DEST     "$MANGOS_GAMEDATA_DOWNLOAD_DEST"
  [[ -n "${MANGOS_GAMEDATA_DOWNLOAD_PIDFILE:-}" ]]   && config_set GAMEDATA_DOWNLOAD_PIDFILE  "$MANGOS_GAMEDATA_DOWNLOAD_PIDFILE"

  local r="$MANGOS_REALM_NAME"
  config_set "REALM_${r}_CORE"         "$MANGOS_REALM_CORE"
  config_set "REALM_${r}_NAME"         "$MANGOS_REALM_DISPLAY"
  config_set "REALM_${r}_ADDRESS"      "$MANGOS_REALM_ADDRESS"
  config_set "REALM_${r}_WORLD_PORT"   "$MANGOS_REALM_WORLD_PORT"
  config_set "REALM_${r}_DB_AUTH"      "mangos_auth"
  config_set "REALM_${r}_DB_CHAR"      "mangos_character0"
  config_set "REALM_${r}_DB_WORLD"     "mangos_world0"
  config_set "REALM_${r}_INSTALLED_AT" "$(date -u +'%Y-%m-%dT%H:%M:%SZ')"
  config_set "REALM_${r}_STATUS"       "preflight"

  chmod 0640 -- "$MANGOS_CONFIG_FILE" 2>/dev/null || true

  secrets_set DB_ADMIN_PASSWORD "$MANGOS_DB_ADMIN_PASSWORD"
  chmod 0600 -- "$MANGOS_SECRETS_FILE" 2>/dev/null || true

  ui_status_ok "config:  $MANGOS_CONFIG_FILE"
  ui_status_ok "secrets: $MANGOS_SECRETS_FILE"
}

# --- helpers -----------------------------------------------------------------

# 24 chars of [A-Za-z0-9], sufficient for auto-generated DB admin passwords.
_generate_password() {
  local len="${1:-24}"
  LC_ALL=C tr -dc 'A-Za-z0-9' </dev/urandom | head -c "$len" || true
}
