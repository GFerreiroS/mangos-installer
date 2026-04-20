#!/usr/bin/env bash
# mangos-installer — phase 09: copy built binaries into realm bin/ and gamedata/
# SPDX-License-Identifier: GPL-2.0-only
# See CLAUDE.md for design, README.md for usage
# shellcheck disable=SC2154
#
# Takes the artifacts from $BUILD_DIR/install/ and scatters them across
# the realm's bin/ (the daemon binaries) and gamedata/ (the extractor
# tools and their helper scripts). Config files (.conf.dist) are handled
# by phase 10.

run_phase_09() {
  MANGOS_CURRENT_PHASE="phase-09-install-binaries"
  ui_phase_header 9 14 "install binaries"

  if state_has_completed "$MANGOS_CURRENT_PHASE"; then
    ui_status_ok "already done — skipping"
    return 0
  fi

  mangos_user_exists || die "mangos user missing (phase 1 must run first)"
  : "${MANGOS_REALM_NAME:?MANGOS_REALM_NAME not set}"

  local realm_dir="$MANGOS_ROOT/$MANGOS_REALM_NAME"
  local install_prefix="${realm_dir}/build/install"
  local bin_out="${realm_dir}/bin"
  local gamedata_out="${realm_dir}/gamedata"

  [[ -d "$install_prefix/bin" ]] || die "no build artifacts at $install_prefix/bin (phase 8 must run first)"

  # Daemons into bin/.
  install -m 0755 -o "$MANGOS_USER" -g "$MANGOS_USER" \
    -- "$install_prefix/bin/mangosd" "$bin_out/mangosd"
  install -m 0755 -o "$MANGOS_USER" -g "$MANGOS_USER" \
    -- "$install_prefix/bin/realmd"  "$bin_out/realmd"
  ui_status_ok "installed mangosd + realmd to $bin_out"

  # Extractor tools into gamedata/. These are per-core: the build outputs a
  # variable number of *-extractor binaries plus some helper .sh scripts
  # and offmesh.txt for pathfinding. We copy whatever exists.
  local tools_src="$install_prefix/bin/tools"
  if [[ -d "$tools_src" ]]; then
    local copied=0
    local f
    for f in "$tools_src"/*-extractor "$tools_src"/*.sh "$tools_src"/offmesh.txt; do
      [[ -e "$f" ]] || continue
      local base
      base=$(basename -- "$f")
      local mode=0755
      [[ "$base" == *.txt ]] && mode=0644
      install -m "$mode" -o "$MANGOS_USER" -g "$MANGOS_USER" \
        -- "$f" "$gamedata_out/$base"
      copied=$(( copied + 1 ))
    done
    ui_status_ok "installed $copied extractor file(s) to $gamedata_out"
  else
    log_warn "no tools/ directory at $tools_src; phase 12 may fail without extractors"
  fi

  state_mark_complete "$MANGOS_CURRENT_PHASE"
}
