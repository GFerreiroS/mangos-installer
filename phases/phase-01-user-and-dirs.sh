#!/usr/bin/env bash
# mangos-installer — phase 01: create mangos user + directory tree, migrate bootstrap state
# SPDX-License-Identifier: GPL-2.0-only
# See CLAUDE.md for design, README.md for usage
# shellcheck disable=SC2154
#
# Idempotent. On first run: useradd -m mangos, scaffold
#   $MANGOS_ROOT/{opt,.installer/{logs,state},<realm>/{source,database,
#                 build,bin,etc,gamedata,logs,backups}}
# and migrate the bootstrap-staging config, state, and boot log into
# $MANGOS_ROOT/.installer/. The M1-stub completion markers for phases
# 2-14 are dropped during migration; only phase-00 is preserved so the
# real phases 2-10 run fresh on first M2 run.
#
# On re-run: detects that user + install root already exist and skips.
# If state says complete but reality doesn't match (e.g., M1 stub marker
# left over and mangos user was never created), self-heals by clearing
# the stale marker and doing the real work.

run_phase_01() {
  MANGOS_CURRENT_PHASE="phase-01-user-and-dirs"
  ui_phase_header 1 14 "user and dirs"

  if state_has_completed "$MANGOS_CURRENT_PHASE"; then
    if mangos_user_exists && [[ -d "$MANGOS_DEFAULT_INSTALL_ROOT" ]] \
       && [[ -d "$MANGOS_DEFAULT_INSTALL_ROOT/.installer" ]]; then
      ui_status_ok "already done — skipping"
      return 0
    fi
    ui_status_warn "state says phase 1 complete but user/root missing; redoing"
    state_reset "$MANGOS_CURRENT_PHASE"
  fi

  privilege_require_root

  _phase_01_create_user
  _phase_01_create_tree
  _phase_01_migrate_bootstrap
  _phase_01_finalize_ownership

  state_mark_complete "$MANGOS_CURRENT_PHASE"
  ui_status_ok "user + dirs ready at $MANGOS_ROOT"
}

# --- user --------------------------------------------------------------------

_phase_01_create_user() {
  local user="$MANGOS_DEFAULT_USER"
  local root="$MANGOS_DEFAULT_INSTALL_ROOT"

  if id -u "$user" >/dev/null 2>&1; then
    ui_status_ok "user '$user' already exists (uid=$(id -u "$user"))"
  else
    # Pre-existing /home/mangos without a mangos user is the "previous
    # operator left stuff behind" case. Warn and confirm before useradd
    # would merge our tree with theirs.
    if [[ -d "/home/$user" ]] && [[ -n "$(ls -A "/home/$user" 2>/dev/null)" ]]; then
      ui_status_warn "/home/$user exists and is non-empty but user '$user' does not"
      ui_status_warn "contents may be left over from a previous install or unrelated setup"
      if ! ui_prompt_yes_no "create user '$user' with that as its home anyway?" \
                            "no" "MANGOS_REUSE_HOME"; then
        die "aborted — resolve /home/$user manually (remove it or move it aside) and re-run"
      fi
    fi
    useradd -m -s /bin/bash -c "MaNGOS server" "$user" \
      || die "failed to create user '$user'"
    ui_status_ok "created user '$user'"
  fi
  export MANGOS_USER="$user"

  # Detect "install root already has unrelated content". We only care
  # when the dir exists, is non-empty, and does NOT look like one of our
  # own prior installs (presence of .installer/ or a realm-named dir).
  if [[ -d "$root" ]] && [[ -n "$(ls -A "$root" 2>/dev/null)" ]] \
     && [[ ! -d "$root/.installer" ]]; then
    ui_status_warn "$root exists and is non-empty but has no .installer/ metadata"
    ui_status_warn "this is not a mangos-installer install — contents may be clobbered"
    if ! ui_prompt_yes_no "continue and scaffold on top?" \
                          "no" "MANGOS_REUSE_INSTALL_ROOT"; then
      die "aborted — move $root aside (or rm -rf) and re-run"
    fi
  fi
}

# --- directory tree ----------------------------------------------------------

_phase_01_create_tree() {
  local root="$MANGOS_DEFAULT_INSTALL_ROOT"
  local realm="${MANGOS_REALM_NAME:?MANGOS_REALM_NAME not set (phase 0 should have set it)}"

  install -d -m 0755 -- "$root"
  install -d -m 0755 -- "$root/opt"
  install -d -m 0755 -- "$root/.installer"
  install -d -m 0755 -- "$root/.installer/logs"
  install -d -m 0755 -- "$root/.installer/state"
  install -d -m 0755 -- "$root/.installer/build-cache"

  install -d -m 0755 -- "$root/$realm"
  install -d -m 0755 -- "$root/$realm/source"
  install -d -m 0755 -- "$root/$realm/database"
  install -d -m 0755 -- "$root/$realm/build"
  install -d -m 0755 -- "$root/$realm/bin"
  install -d -m 0750 -- "$root/$realm/etc"
  install -d -m 0755 -- "$root/$realm/gamedata"
  install -d -m 0755 -- "$root/$realm/logs"
  install -d -m 0755 -- "$root/$realm/backups"

  # /etc/mangos-installer/ was created in phase 0; re-affirm perms.
  install -d -m 0700 -o root -g root -- "$MANGOS_SECRETS_DIR"

  export MANGOS_ROOT="$root"
  ui_status_ok "scaffolded directory tree under $root"
}

# --- migration from bootstrap staging ----------------------------------------

_phase_01_migrate_bootstrap() {
  local root="$MANGOS_DEFAULT_INSTALL_ROOT"
  local ts
  ts=$(date -u +'%Y%m%d-%H%M%S')

  # 1) Log file: create the real log, append the bootstrap log, switch env.
  local new_log="$root/.installer/logs/install-${ts}.log"
  : > "$new_log"
  if [[ -n "${MANGOS_LOG_FILE:-}" ]] && [[ -f "$MANGOS_LOG_FILE" ]]; then
    cat -- "$MANGOS_LOG_FILE" >> "$new_log" 2>/dev/null || true
    printf '%s [INFO] [phase-01-user-and-dirs] --- log migrated from %s ---\n' \
      "$(date -u +'%Y-%m-%d %H:%M:%S')" "$MANGOS_LOG_FILE" >> "$new_log"
    rm -f -- "$MANGOS_LOG_FILE"
  fi
  MANGOS_LOG_FILE="$new_log"
  export MANGOS_LOG_FILE
  ui_status_ok "log: $MANGOS_LOG_FILE"

  # 2) Config file: move bootstrap config to the final location.
  local old_config="${MANGOS_CONFIG_FILE:-$MANGOS_BOOTSTRAP_STAGING/config.env}"
  local new_config="$root/.installer/config.env"
  if [[ "$old_config" != "$new_config" ]] && [[ -f "$old_config" ]]; then
    mv -- "$old_config" "$new_config"
  elif [[ ! -f "$new_config" ]]; then
    : > "$new_config"
  fi
  chmod 0644 -- "$new_config"
  MANGOS_CONFIG_FILE="$new_config"
  export MANGOS_CONFIG_FILE
  ui_status_ok "config: $MANGOS_CONFIG_FILE"

  # 3) State file: start a fresh global.state keyed only to phase-00. This
  # deliberately drops the milestone-1 stub completion markers for phases
  # 2-14 so the real implementations run on first M2 execution.
  local new_state="$root/.installer/state/global.state"
  local old_state="${MANGOS_STATE_FILE:-}"
  {
    if [[ -n "$old_state" ]] && [[ -f "$old_state" ]] \
       && grep -q '^phase-00-preflight completed ' "$old_state"; then
      grep '^phase-00-preflight completed ' "$old_state" | tail -n 1
    fi
  } > "$new_state"
  chmod 0644 -- "$new_state"
  MANGOS_STATE_FILE="$new_state"
  export MANGOS_STATE_FILE
  ui_status_ok "state: $MANGOS_STATE_FILE"

  # 4) Remove the bootstrap staging dir if it was used (leave /etc/mangos-installer/).
  if [[ -d "$MANGOS_BOOTSTRAP_STAGING" ]]; then
    rm -rf -- "$MANGOS_BOOTSTRAP_STAGING"
    log_info "removed bootstrap staging dir"
  fi
}

# --- ownership ---------------------------------------------------------------

_phase_01_finalize_ownership() {
  local root="$MANGOS_DEFAULT_INSTALL_ROOT"
  local user="$MANGOS_USER"
  chown -R "${user}:${user}" -- "$root"
  # etc/ stays 0750 mangos:mangos (already set); secrets.env stays root:root.
  ui_status_ok "ownership: $user:$user under $root"
}
