#!/usr/bin/env bash
# mangos-installer — phase 12: extract dbc / maps / vmaps / mmaps from the client
# SPDX-License-Identifier: GPL-2.0-only
# See CLAUDE.md for design, README.md for usage
# shellcheck disable=SC2154
#
# We invoke the extractor binaries directly rather than drive the
# interactive upstream ExtractResources.sh with `expect`. The mangos
# extractors are designed to run non-interactively when given the
# expected CWD (the gamedata/ dir containing Data/) — they write their
# outputs next to Data/ and exit.
#
# Runtime is dominated by mmaps_generator on multi-core machines —
# expect 30 min – 2 h on x86_64, 1–3 h on aarch64. We emit a heartbeat
# every 60s so operators can see the phase is alive.
#
# On success we clean up the extractor binaries and helper scripts
# (they are not needed at runtime). The MPQ Data/ stays on disk; it is
# small compared to the extracted outputs and operators may want to
# re-extract after patching.

run_phase_12() {
  MANGOS_CURRENT_PHASE="phase-12-gamedata-extract"
  ui_phase_header 12 14 "gamedata extract"

  : "${MANGOS_REALM_NAME:?MANGOS_REALM_NAME not set}"
  local realm_dir="$MANGOS_ROOT/$MANGOS_REALM_NAME"
  local gd="$realm_dir/gamedata"

  if state_has_completed "$MANGOS_CURRENT_PHASE"; then
    if gamedata_extract_products_exist "$gd"; then
      ui_status_ok "already done — skipping"
      return 0
    fi
    ui_status_warn "state says done but dbc/maps/vmaps/mmaps missing; redoing"
    state_reset "$MANGOS_CURRENT_PHASE"
  fi

  [[ -d "$gd/Data" ]] || die "gamedata/Data not present (phase 11 must run first)"
  find "$gd/Data" -maxdepth 1 -type f -iname '*.MPQ' -print -quit 2>/dev/null \
    | grep -q . || die "gamedata/Data contains no .MPQ files (phase 11 must run first)"

  _phase_12_make_writable "$gd"

  # 1) map-extractor — produces dbc/ + maps/. Run first; vmap and mmap
  #    depend on it indirectly (vmap extracts from MPQs; mmap walks maps).
  _phase_12_run_map_extractor  "$gd"

  # 2) vmap-extractor + vmap_assembler — produces vmaps/.
  _phase_12_run_vmap_extractor "$gd"

  # 3) mmaps_generator — longest step. Produces mmaps/.
  _phase_12_run_mmaps_generator "$gd"

  _phase_12_verify  "$gd"
  _phase_12_cleanup "$gd"

  state_mark_complete "$MANGOS_CURRENT_PHASE"
  ui_status_ok "gamedata extraction complete"
}

# ---------------------------------------------------------------------------

_phase_12_make_writable() {
  local gd="$1"
  # Upstream guide does this; some MPQ tooling insists on writable CWD.
  chmod -R u+w -- "$gd" 2>/dev/null || true
}

# Pick the first existing binary from a list (different mangos versions
# use slightly different names). Prints the absolute path.
_phase_12_pick_bin() {
  local gd="$1"; shift
  local name
  for name in "$@"; do
    if [[ -x "$gd/$name" ]]; then
      printf '%s\n' "$gd/$name"
      return 0
    fi
  done
  return 1
}

# Run a binary as mangos inside the gamedata dir, with a 60s heartbeat.
_phase_12_run_in_gd() {
  local gd="$1" label="$2"; shift 2
  local bin="$1"; shift
  [[ -x "$bin" ]] || { log_warn "$label: binary missing: $bin"; return 0; }
  ui_status_info "$label: $(basename -- "$bin") (this can take a while)..."
  local start_ts elapsed
  start_ts=$(date +%s)

  local script
  script=$(mktemp --tmpdir "mi-extract.XXXXXX.sh")
  {
    printf '#!/usr/bin/env bash\n'
    printf 'set -euo pipefail\n'
    printf 'cd %q\n' "$gd"
    printf '%q' "$bin"
    local a
    for a in "$@"; do
      printf ' %q' "$a"
    done
    printf '\n'
  } > "$script"
  chmod 0755 -- "$script"

  # Run the script as mangos in the background; heartbeat the log.
  local log_tag="[extract:$(basename -- "$bin")]"
  (
    run_script_as_mangos "$script" >>"$MANGOS_LOG_FILE" 2>&1
    printf '%d\n' "$?" > "${script}.exit"
  ) &
  local pid=$!

  while kill -0 -- "$pid" 2>/dev/null; do
    sleep 60
    elapsed=$(( $(date +%s) - start_ts ))
    ui_status_info "$label: still running (${elapsed}s elapsed)"
    log_info "$log_tag heartbeat ${elapsed}s"
  done
  wait "$pid" 2>/dev/null || true

  local rc=1
  [[ -f "${script}.exit" ]] && rc=$(cat -- "${script}.exit")
  rm -f -- "$script" "${script}.exit"

  elapsed=$(( $(date +%s) - start_ts ))
  if [[ "$rc" != "0" ]]; then
    die "$label failed after ${elapsed}s (exit=$rc; see $MANGOS_LOG_FILE)"
  fi
  ui_status_ok "$label done in ${elapsed}s"
}

_phase_12_run_map_extractor() {
  local gd="$1"
  local bin
  bin=$(_phase_12_pick_bin "$gd" map-extractor MapExtractor) \
    || { log_warn "no map-extractor binary; skipping"; return 0; }
  # Clean outputs from any previous partial run to avoid interactive prompts.
  rm -rf -- "$gd/dbc" "$gd/maps"
  _phase_12_run_in_gd "$gd" "map-extractor" "$bin"
}

_phase_12_run_vmap_extractor() {
  local gd="$1"
  local ext asm
  ext=$(_phase_12_pick_bin "$gd" vmap-extractor VmapExtractor vmap_extractor) \
    || { log_warn "no vmap-extractor binary; skipping"; return 0; }
  # vmap-extractor aborts if Buildings/ or vmaps/ already exist (left by a
  # previous partial run) and waits for keyboard input. Always clean first.
  rm -rf -- "$gd/Buildings" "$gd/vmaps"
  _phase_12_run_in_gd "$gd" "vmap-extractor" "$ext"

  if asm=$(_phase_12_pick_bin "$gd" vmap_assembler vmap-assembler VmapAssembler 2>/dev/null); then
    _phase_12_run_in_gd "$gd" "vmap_assembler" "$asm"
  fi
}

_phase_12_run_mmaps_generator() {
  local gd="$1"
  local bin
  bin=$(_phase_12_pick_bin "$gd" mmap-extractor mmaps_generator MoveMapGen MoveMapGenerator) || {
    ui_status_warn "mmap-extractor not found in $gd — resetting phase 9 to re-copy tools"
    state_reset "phase-09-install-binaries"
    die "mmap-extractor missing; re-run the installer (phase 9 will re-copy tools)"
  }
  rm -rf -- "$gd/mmaps"
  mkdir -p -- "$gd/mmaps"

  local cores
  cores=$(nproc 2>/dev/null || echo 1)

  # Collect unique map IDs from maps/*.map filenames (MMMTT.map → MMM).
  local -a unique_ids=()
  local f id
  while IFS= read -r -d '' f; do
    id=$(basename -- "$f")
    id=${id%.map}
    id=${id%%_*}
    id=$(( 10#$id ))   # strip leading zeros
    unique_ids+=("$id")
  done < <(find "$gd/maps" -maxdepth 1 -name '*.map' -print0 2>/dev/null)
  # Sort + deduplicate in-place
  local deduped
  deduped=$(printf '%s\n' "${unique_ids[@]}" | sort -un)
  mapfile -t unique_ids <<< "$deduped"

  if [[ ${#unique_ids[@]} -eq 0 ]]; then
    die "no map files found in $gd/maps (map-extractor must run first)"
  fi
  ui_status_info "mmap-extractor: ${#unique_ids[@]} maps, $cores parallel worker(s)"

  local offmesh_arg=""
  [[ -f "$gd/offmesh.txt" ]] && offmesh_arg="--offMeshInput offmesh.txt"

  # FIFO semaphore: pre-load $cores tokens; each worker consumes one on
  # start and returns one on finish, keeping exactly $cores jobs active.
  local fifo fail_dir start_ts
  fifo=$(mktemp -u --tmpdir "mi-mmap-fifo.XXXXXX")
  fail_dir=$(mktemp -d --tmpdir "mi-mmap-fail.XXXXXX")
  mkfifo "$fifo"
  exec 3<>"$fifo"
  local i; for ((i=0; i<cores; i++)); do printf 'x' >&3; done
  start_ts=$(date +%s)

  for id in "${unique_ids[@]}"; do
    read -r -n1 -u3       # acquire token
    (
      set +e
      cd "$gd"
      # shellcheck disable=SC2086
      "$bin" $offmesh_arg "$id" >>"$MANGOS_LOG_FILE" 2>&1 \
        || touch "$fail_dir/$id"
      printf 'x' >&3      # release token
    ) &
  done
  wait
  exec 3>&-
  rm -f "$fifo"

  local failed elapsed
  failed=$(find "$fail_dir" -maxdepth 1 -type f 2>/dev/null | wc -l)
  rm -rf "$fail_dir"
  elapsed=$(( $(date +%s) - start_ts ))

  [[ $failed -gt 0 ]] && log_warn "mmap-extractor: $failed map(s) had errors (see log)"
  ui_status_ok "mmap-extractor: ${#unique_ids[@]} maps in ${elapsed}s ($failed failed)"
}

_phase_12_verify() {
  local gd="$1"
  local d missing=""
  for d in dbc maps vmaps mmaps; do
    if [[ ! -d "$gd/$d" ]] || [[ -z "$(ls -A -- "$gd/$d" 2>/dev/null)" ]]; then
      missing+=" $d"
    fi
  done
  [[ -n "$missing" ]] && die "extraction produced no output for:$missing"
  ui_status_ok "outputs present: dbc maps vmaps mmaps"
}

_phase_12_cleanup() {
  local gd="$1"
  local f
  # Keep Data/ and the four output directories (dbc/maps/vmaps/mmaps);
  # remove the extractor binaries and helper scripts which are not needed
  # at runtime. Allowed to fail (operator may have already cleaned up).
  for f in "$gd"/*-extractor "$gd"/*Extractor "$gd"/mmaps_generator \
           "$gd"/MoveMapGen "$gd"/MoveMapGenerator \
           "$gd"/vmap_assembler "$gd"/VmapAssembler \
           "$gd"/*.sh "$gd"/offmesh.txt; do
    [[ -e "$f" ]] && rm -rf -- "$f"
  done
  log_info "post-extract cleanup: removed extractor binaries and helper scripts"
}
