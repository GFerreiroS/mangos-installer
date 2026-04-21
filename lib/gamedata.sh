#!/usr/bin/env bash
# mangos-installer — gamedata validation and preparation
# SPDX-License-Identifier: GPL-2.0-only
# See CLAUDE.md for design, README.md for usage
# shellcheck shell=bash
#
# The WoW 1.12.x client MUST sit at <realm>/gamedata/ with a Data/ subdir
# containing the MPQ archives. The extractor binaries (map-extractor,
# vmap-extractor, mmaps_generator) run in the realm gamedata/ dir and
# walk Data/ to produce dbc/ maps/ vmaps/ mmaps/ outputs next to it.

# MPQs the 1.12.x map/vmap extractors open by name (from mangoszero extractor source).
_gamedata_required_mpqs_zero=( "base.MPQ" "dbc.MPQ" "misc.MPQ" "model.MPQ" "sound.MPQ"
                               "terrain.MPQ" "texture.MPQ" "wmo.MPQ" "patch.MPQ" "patch-2.MPQ" )
# Expansion MPQs that must NOT be present for core 'zero'.
_gamedata_forbidden_mpqs_zero=( "expansion.MPQ" "lichking.MPQ" "expansion1.MPQ" "expansion2.MPQ" "expansion3.MPQ" )

# gamedata_find_data_dir <root> — walk up to 4 levels under <root> and
# print the first directory named Data/ that contains at least one .MPQ file.
# Custom/repack clients (SoloCraft, RetroWoW) don't ship common.MPQ by name
# but still have all vanilla data split across other MPQs — the extractor
# opens all *.mpq files and doesn't require specific names.
gamedata_find_data_dir() {
  local root="$1"
  [[ -d "$root" ]] || return 1
  local hit
  # Prefer a Data/ dir that has any .MPQ file directly inside it.
  hit=$(find "$root" -maxdepth 4 -type d -iname 'Data' -print0 2>/dev/null \
        | while IFS= read -r -d '' d; do
            if find "$d" -maxdepth 1 -type f -iname '*.MPQ' -print -quit 2>/dev/null | grep -q .; then
              printf '%s\n' "$d"
              break
            fi
          done | head -n 1)
  [[ -z "$hit" ]] && return 1
  # Return the client root (parent of Data/).
  printf '%s\n' "${hit%/*}"
}

# gamedata_validate_structure <path> [<core>] — checks that <path>
# (possibly nested) contains a Data/ with the required MPQs for the
# named core, and does NOT contain expansion MPQs when core=zero.
gamedata_validate_structure() {
  local path="$1" core="${2:-zero}"
  [[ -n "$path" ]] || { log_error "gamedata_validate_structure: empty path"; return 1; }
  [[ -d "$path" ]] || { log_error "gamedata_validate_structure: not a directory: $path"; return 1; }

  local client_root data_dir
  client_root=$(gamedata_find_data_dir "$path") || {
    log_error "no Data/ directory with .MPQ files found under $path (searched 4 levels deep)"
    log_error "directory tree under $path (3 levels):"
    find "$path" -maxdepth 3 -type d 2>/dev/null | sort | while IFS= read -r d; do
      log_error "  dir: ${d#"$path/"}"
    done
    local found_mpqs
    found_mpqs=$(find "$path" -maxdepth 5 -type f -iname '*.MPQ' 2>/dev/null | sort)
    if [[ -n "$found_mpqs" ]]; then
      log_error "MPQ files found (not in a Data/ dir):"
      while IFS= read -r f; do log_error "  $f"; done <<< "$found_mpqs"
    else
      log_error "no .MPQ files found anywhere under $path"
    fi
    return 1
  }
  data_dir="${client_root}/Data"
  [[ -d "$data_dir" ]] || data_dir=$(find "$client_root" -maxdepth 1 -type d -iname 'Data' | head -n 1)
  [[ -d "$data_dir" ]] || { log_error "no Data/ directory at $client_root"; return 1; }

  local mpq missing="" forbidden_found=""
  local -n req_ref="_gamedata_required_mpqs_${core}"
  local -n forb_ref="_gamedata_forbidden_mpqs_${core}"

  for mpq in "${req_ref[@]}"; do
    if ! find "$data_dir" -maxdepth 1 -type f -iname "$mpq" -print -quit 2>/dev/null | grep -q .; then
      missing+=" $mpq"
    fi
  done
  if [[ -n "$missing" ]]; then
    log_error "gamedata missing required MPQs for core '$core':$missing"
    local found_mpqs
    found_mpqs=$(find "$data_dir" -maxdepth 1 -type f -iname '*.MPQ' 2>/dev/null | sort)
    if [[ -n "$found_mpqs" ]]; then
      log_error "MPQs present in Data/:"
      while IFS= read -r f; do log_error "  $(basename -- "$f")"; done <<< "$found_mpqs"
    else
      log_error "no .MPQ files found in $data_dir"
    fi
    return 1
  fi

  for mpq in "${forb_ref[@]}"; do
    if find "$data_dir" -maxdepth 1 -type f -iname "$mpq" -print -quit 2>/dev/null | grep -q .; then
      forbidden_found+=" $mpq"
    fi
  done
  if [[ -n "$forbidden_found" ]]; then
    log_error "gamedata contains expansion MPQs not compatible with core '$core':$forbidden_found"
    return 1
  fi

  # Export so the caller (phase 11) knows where the real Data/ is.
  export MANGOS_GAMEDATA_CLIENT_ROOT="$client_root"
  export MANGOS_GAMEDATA_DATA_DIR="$data_dir"
  log_info "gamedata validated: client_root=$client_root data_dir=$data_dir"
  return 0
}

# gamedata_move_to_realm <source-client-root> <realm>
# Moves (or symlinks) <source>/Data into <realm_dir>/gamedata/Data.
# Prefers a rename (mv) when on the same filesystem; falls back to a
# recursive copy otherwise. Skips cleanly if Data/ already lives in the
# realm gamedata dir.
gamedata_move_to_realm() {
  local source="$1" realm="${2:-$MANGOS_REALM_NAME}"
  local realm_dir="$MANGOS_ROOT/$realm"
  local target="$realm_dir/gamedata/Data"

  [[ -n "$source" ]] || { log_error "gamedata_move_to_realm: no source"; return 1; }
  [[ -d "$source/Data" ]] || {
    # source may already be a Data/ dir
    if [[ -f "$source/common.MPQ" ]] || [[ -f "$source/Common.MPQ" ]]; then
      source="$(dirname -- "$source")"
    else
      log_error "gamedata_move_to_realm: $source/Data not found"
      return 1
    fi
  }

  install -d -m 0755 -o "$MANGOS_USER" -g "$MANGOS_USER" -- "$realm_dir/gamedata"

  if [[ -d "$target" ]] && [[ -n "$(ls -A -- "$target" 2>/dev/null)" ]]; then
    log_info "gamedata Data/ already present at $target — leaving in place"
    return 0
  fi

  # If source is under /home/mangos (same fs as target) try rename first.
  if mv -- "$source/Data" "$target" 2>/dev/null; then
    log_info "gamedata: renamed $source/Data -> $target"
  else
    log_info "gamedata: copying $source/Data -> $target (cross-filesystem)"
    cp -a -- "$source/Data" "$target" || return 1
  fi
  chown -R "$MANGOS_USER:$MANGOS_USER" -- "$target"
  return 0
}

# gamedata_extract_products_exist <realm_gamedata_dir>
# Returns 0 if all four extractor outputs (dbc/, maps/, vmaps/, mmaps/)
# exist and are non-empty. Used for phase-12 idempotence.
gamedata_extract_products_exist() {
  local gd="$1"
  local d
  for d in dbc maps vmaps mmaps; do
    [[ -d "$gd/$d" ]] || return 1
    [[ -n "$(ls -A -- "$gd/$d" 2>/dev/null)" ]] || return 1
  done
  return 0
}
