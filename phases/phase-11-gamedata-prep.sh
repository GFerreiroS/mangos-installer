#!/usr/bin/env bash
# mangos-installer — phase 11: resolve gamedata source (path/url/manual), validate, move
# SPDX-License-Identifier: GPL-2.0-only
# See CLAUDE.md for design, README.md for usage
# shellcheck disable=SC2154
#
# Branches on GAMEDATA_SOURCE (persisted by phase 0):
#   - path: user-provided local directory — validate then move into
#     <realm>/gamedata/Data/
#   - url: wait for the background curl PID started by phase 0; extract
#     the archive; validate; move
#   - manual: print instructions with the expected target path and exit
#     0 (subsequent phases will be skipped this run). The operator
#     re-runs the installer after placing the files; phase 11 then
#     re-validates and continues.

run_phase_11() {
  MANGOS_CURRENT_PHASE="phase-11-gamedata-prep"
  ui_phase_header 11 14 "gamedata prep"

  : "${MANGOS_REALM_NAME:?MANGOS_REALM_NAME not set}"
  local realm_dir="$MANGOS_ROOT/$MANGOS_REALM_NAME"
  local gd="$realm_dir/gamedata"
  local target="$gd/Data"

  # Idempotence: Data/ populated + WoW.exe present (extractors need it).
  if state_has_completed "$MANGOS_CURRENT_PHASE" \
     && [[ -d "$target" ]] \
     && [[ -n "$(find "$target" -maxdepth 1 -type f -iname '*.MPQ' -print -quit 2>/dev/null)" ]] \
     && [[ -f "$gd/WoW.exe" || -f "$gd/wow" || -f "$gd/Wow.exe" ]]; then
    ui_status_ok "already done — skipping"
    return 0
  fi

  mangos_user_exists || die "mangos user missing (phase 1 must run first)"

  local source_mode core
  source_mode=$(config_get GAMEDATA_SOURCE)
  core="${MANGOS_REALM_CORE:-$(config_get "REALM_${MANGOS_REALM_NAME}_CORE")}"
  [[ -n "$source_mode" ]] || die "GAMEDATA_SOURCE not set in config (phase 0 must run first)"

  case "$source_mode" in
    path)   _phase_11_from_path   "$gd" "$core" ;;
    url)    _phase_11_from_url    "$gd" "$core" ;;
    manual) _phase_11_manual_stop "$gd" ;;
    *)      die "unknown GAMEDATA_SOURCE: $source_mode" ;;
  esac

  state_mark_complete "$MANGOS_CURRENT_PHASE"
}

# --- path --------------------------------------------------------------------

_phase_11_from_path() {
  local gd="$1" core="$2"
  local user_path
  user_path=$(config_get GAMEDATA_PATH)
  [[ -n "$user_path" ]] || die "GAMEDATA_PATH not set (phase 0 must run first)"
  [[ -d "$user_path" ]] || die "gamedata path not a directory: $user_path"

  ui_status_info "validating client at $user_path..."
  if ! gamedata_validate_structure "$user_path" "$core"; then
    die "gamedata validation failed; see log for details"
  fi
  ui_status_ok "found Data/ at $MANGOS_GAMEDATA_DATA_DIR"

  if [[ -d "$gd/Data" ]] && [[ -n "$(ls -A -- "$gd/Data" 2>/dev/null)" ]]; then
    ui_status_ok "$gd/Data is already populated; leaving in place"
    return 0
  fi

  ui_status_info "moving Data/ into $gd/Data/ ..."
  gamedata_move_to_realm "$MANGOS_GAMEDATA_CLIENT_ROOT" "$MANGOS_REALM_NAME" \
    || die "failed to move gamedata into $gd/Data"
  ui_status_ok "gamedata in place"
}

# --- url ---------------------------------------------------------------------

_phase_11_from_url() {
  local gd="$1" core="$2"
  local dest pidfile
  dest=$(config_get GAMEDATA_DOWNLOAD_DEST)
  pidfile=$(config_get GAMEDATA_DOWNLOAD_PIDFILE)
  [[ -n "$dest"    ]] || die "GAMEDATA_DOWNLOAD_DEST not set (phase 0 must run first)"
  [[ -n "$pidfile" ]] || die "GAMEDATA_DOWNLOAD_PIDFILE not set (phase 0 must run first)"

  local url
  url=$(config_get GAMEDATA_URL)

  local staging="$gd/.extract"

  _phase_11_prompt_new_url() {
    local reason="$1"
    ui_status_warn "$reason"
    if ui_prompt_yes_no "provide a different URL and retry?" "no" "MANGOS_CHANGE_GAMEDATA_URL"; then
      url=$(ui_prompt_text "new gamedata URL" "" "MANGOS_GAMEDATA_URL")
      [[ -n "$url" ]] || die "URL cannot be empty"
      local proto_status=0
      download_validate_protocol "$url" || proto_status=$?
      if [[ "$proto_status" -eq 1 ]]; then
        ui_status_warn "URL uses an insecure protocol (http/ftp)"
        ui_prompt_yes_no "continue with insecure URL?" "no" "MANGOS_ALLOW_INSECURE_URL" \
          || die "aborted"
      elif [[ "$proto_status" -gt 1 ]]; then
        die "unsupported URL protocol in '$url'"
      fi
      config_set GAMEDATA_URL "$url"
      rm -f -- "${dest}.part" "$dest"
      rm -rf -- "$staging"
    else
      die "gamedata unavailable; re-run the installer to retry"
    fi
  }

  while true; do
    # ---- download ----
    if [[ ! -s "$dest" ]]; then
      if [[ ! -f "$pidfile" ]]; then
        [[ -n "$url" ]] || die "GAMEDATA_URL not set and no archive at $dest"
        ui_status_info "starting download: $url"
        rm -f -- "${dest}.part"
        download_background "$url" "$dest" "$pidfile"
      fi

      ui_status_info "waiting for download to finish (stalls >60s will fail automatically)..."
      local rc
      rc=$(download_wait "$pidfile")
      rm -f -- "$pidfile" "${pidfile}.exit"

      if [[ "${rc:-1}" != "0" ]]; then
        _phase_11_prompt_new_url "download failed or stalled (exit=$rc)"
        continue
      fi
      ui_status_ok "download complete: $dest"
    else
      ui_status_ok "archive already on disk: $dest"
    fi

    # ---- extract ----
    rm -rf -- "$staging"
    install -d -m 0755 -o "$MANGOS_USER" -g "$MANGOS_USER" -- "$staging"
    ui_status_info "extracting archive..."
    if ! archive_extract "$dest" "$staging"; then
      rm -f -- "$dest"
      rm -rf -- "$staging"
      _phase_11_prompt_new_url "archive extraction failed — file may be corrupt"
      continue
    fi
    chown -R "$MANGOS_USER:$MANGOS_USER" -- "$staging"

    # ---- validate ----
    ui_status_info "validating extracted client..."
    if ! gamedata_validate_structure "$staging" "$core"; then
      rm -f -- "$dest"
      rm -rf -- "$staging"
      _phase_11_prompt_new_url "gamedata validation failed (see log for required MPQ list)"
      continue
    fi

    break
  done

  ui_status_info "moving Data/ into $gd/Data/ ..."
  gamedata_move_to_realm "$MANGOS_GAMEDATA_CLIENT_ROOT" "$MANGOS_REALM_NAME" \
    || die "failed to move gamedata into $gd/Data"

  rm -rf -- "$staging"
  ui_status_ok "gamedata in place"
}

# --- manual ------------------------------------------------------------------
#
# First run: create empty Data/ and stop with instructions (do NOT mark
# complete, so re-run returns here).
# Re-run: if the operator has placed MPQs, validate — if the structure
# passes, log it and let run_phase_11 mark the phase complete.

_phase_11_manual_stop() {
  local gd="$1"
  local core="${MANGOS_REALM_CORE:-zero}"
  install -d -m 0755 -o "$MANGOS_USER" -g "$MANGOS_USER" -- "$gd/Data"

  # Already populated? Validate and continue.
  if [[ -n "$(find "$gd/Data" -maxdepth 1 -type f -iname '*.MPQ' -print -quit 2>/dev/null)" ]]; then
    ui_status_info "validating client files at $gd/Data/..."
    if gamedata_validate_structure "$gd" "$core"; then
      ui_status_ok "gamedata in place"
      return 0
    fi
    die "gamedata validation failed at $gd/Data (see log)"
  fi

  ui_status_warn "manual gamedata mode selected."
  ui_status_info "place your WoW 1.12.x client Data/ MPQs at:"
  ui_status_info "  $gd/Data/"
  ui_status_info "any standard 1.12.x client layout is accepted (vanilla or repack)"
  ui_status_info "(expansion.MPQ / lichking.MPQ must NOT be present for core 'zero')"
  ui_status_info ""
  ui_status_info "once placed, re-run the installer to continue:"
  ui_status_info "  sudo bash install.sh --dev-mode   # or the curl | sudo bash form"
  log_info "phase 11 manual stop — installer paused; phase will not be marked complete"
  exit 0
}
