#!/usr/bin/env bash
# mangos-installer — phase 06: clone (or update) mangoszero/server + database repos
# SPDX-License-Identifier: GPL-2.0-only
# See CLAUDE.md for design, README.md for usage
# shellcheck disable=SC2154
#
# First per-realm phase. Determines the target ref by querying the GitHub
# releases API (parsed with grep+sed, not jq); falls back to
# MANGOS_FALLBACK_REF when the API is unreachable. Clones or updates both
# the core and database repos under the realm's source/ and database/
# directories. Subsequent phases (7, 8) assume both trees exist at the
# recorded ref.

run_phase_06() {
  MANGOS_CURRENT_PHASE="phase-06-fetch-sources"
  ui_phase_header 6 14 "fetch sources"

  if state_has_completed "$MANGOS_CURRENT_PHASE"; then
    ui_status_ok "already done — skipping"
    return 0
  fi

  mangos_user_exists || die "mangos user missing (phase 1 must run first)"
  : "${MANGOS_REALM_NAME:?MANGOS_REALM_NAME not set}"
  : "${MANGOS_REALM_CORE:?MANGOS_REALM_CORE not set}"

  local ref db_ref
  ref=$(_phase_06_resolve_ref)
  db_ref=$(_phase_06_resolve_db_ref "$ref")
  ui_status_ok "MaNGOS ref: ${ref}  DB ref: ${db_ref}"

  local realm_dir="$MANGOS_ROOT/$MANGOS_REALM_NAME"
  local src="${realm_dir}/source"
  local dbr="${realm_dir}/database"

  _phase_06_clone_or_update "$MANGOS_ZERO_REPO"    "$src" "$ref"
  _phase_06_clone_or_update "$MANGOS_ZERO_DB_REPO" "$dbr" "$db_ref"

  config_set "REALM_${MANGOS_REALM_NAME}_MANGOS_REF"    "$ref"
  config_set "REALM_${MANGOS_REALM_NAME}_MANGOS_DB_REF" "$db_ref"
  export MANGOS_REALM_MANGOS_REF="$ref"
  export MANGOS_REALM_MANGOS_DB_REF="$db_ref"

  state_mark_complete "$MANGOS_CURRENT_PHASE"
  ui_status_ok "source + database trees ready"
}

# Resolve the MaNGOS ref: MANGOS_FORCE_REF (set by update-realm), else
# latest release tag via GitHub API, else fallback. JSON parsed with sed
# (no jq dependency — see CLAUDE.md § 7 M2 and § 9).
_phase_06_resolve_ref() {
  if [[ -n "${MANGOS_FORCE_REF:-}" ]]; then
    printf '%s\n' "$MANGOS_FORCE_REF"
    return 0
  fi
  local api_json ref=""
  if api_json=$(curl -fsSL --max-time 15 "$MANGOS_ZERO_RELEASES_API" 2>>"$MANGOS_LOG_FILE"); then
    ref=$(printf '%s\n' "$api_json" \
      | sed -nE 's/.*"tag_name": *"([^"]+)".*/\1/p' \
      | head -n 1)
  fi
  if [[ -z "$ref" ]]; then
    log_warn "GitHub releases API unreachable or parse failed; using fallback ref"
    ref="$MANGOS_FALLBACK_REF"
  fi
  printf '%s\n' "$ref"
}

# Resolve the database ref: the DB repo has its own release cadence and may
# not carry the same tag as the server. Strategy:
#   1. Check if the server ref exists as a tag in the DB repo (API tags list).
#   2. If not, query the DB repo's own latest release.
#   3. If that also fails, fall back to MANGOS_FALLBACK_REF then HEAD.
_phase_06_resolve_db_ref() {
  local server_ref="$1"

  # Fast path: check if the DB repo has the exact same tag via the tags API.
  local tags_json
  if tags_json=$(curl -fsSL --max-time 15 \
      "https://api.github.com/repos/mangoszero/database/tags?per_page=100" \
      2>>"$MANGOS_LOG_FILE"); then
    if printf '%s\n' "$tags_json" | grep -q "\"${server_ref}\""; then
      printf '%s\n' "$server_ref"
      return 0
    fi
  fi

  # DB doesn't have the server tag — use its own latest release.
  local api_json ref=""
  if api_json=$(curl -fsSL --max-time 15 "$MANGOS_ZERO_DB_RELEASES_API" \
      2>>"$MANGOS_LOG_FILE"); then
    ref=$(printf '%s\n' "$api_json" \
      | sed -nE 's/.*"tag_name": *"([^"]+)".*/\1/p' \
      | head -n 1)
  fi
  if [[ -n "$ref" ]]; then
    log_warn "DB repo has no tag '${server_ref}'; using its own latest release: ${ref}"
    printf '%s\n' "$ref"
    return 0
  fi

  # Last resort: fall back to the same fallback ref as the server.
  log_warn "DB releases API also failed; using fallback ref ${MANGOS_FALLBACK_REF}"
  printf '%s\n' "$MANGOS_FALLBACK_REF"
}

# Idempotent: clones if missing, fetches+checks-out if present, updates
# submodules either way. Runs as the mangos user so working trees have
# correct ownership.
_phase_06_clone_or_update() {
  local repo_url="$1" dest="$2" ref="$3"
  local script
  script=$(mktemp --tmpdir "mi-git.XXXXXX.sh")
  cat > "$script" <<GIT
#!/usr/bin/env bash
set -euo pipefail
repo_url="$repo_url"
dest="$dest"
ref="$ref"
if [[ -d "\$dest/.git" ]]; then
  cd "\$dest"
  git remote set-url origin "\$repo_url"
  git fetch --tags --prune origin
  git checkout --force "\$ref"
  git submodule sync --recursive
  git submodule update --init --recursive
else
  rm -rf -- "\$dest"
  git clone --recursive --branch "\$ref" "\$repo_url" "\$dest"
fi
GIT
  chmod 0755 -- "$script"

  ui_status_info "$(basename -- "$dest"): fetching ${repo_url##*/}@${ref}..."
  if ! run_script_as_mangos "$script" >>"$MANGOS_LOG_FILE" 2>&1; then
    rm -f -- "$script"
    die "git clone/update failed for $repo_url at $ref (see $MANGOS_LOG_FILE)"
  fi
  rm -f -- "$script"
  ui_status_ok "$(basename -- "$dest"): $(cd "$dest" && git rev-parse --short HEAD 2>/dev/null || echo '?')"
}
