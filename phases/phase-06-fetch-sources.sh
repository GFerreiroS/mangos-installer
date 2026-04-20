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

  local ref
  ref=$(_phase_06_resolve_ref)
  ui_status_ok "MaNGOS ref: ${ref}"

  local realm_dir="$MANGOS_ROOT/$MANGOS_REALM_NAME"
  local src="${realm_dir}/source"
  local dbr="${realm_dir}/database"

  _phase_06_clone_or_update "$MANGOS_ZERO_REPO"    "$src" "$ref"
  _phase_06_clone_or_update "$MANGOS_ZERO_DB_REPO" "$dbr" "$ref"

  config_set "REALM_${MANGOS_REALM_NAME}_MANGOS_REF" "$ref"
  export MANGOS_REALM_MANGOS_REF="$ref"

  state_mark_complete "$MANGOS_CURRENT_PHASE"
  ui_status_ok "source + database trees ready"
}

# Resolve the MaNGOS ref: latest release tag via GitHub API, or fallback.
# Parses JSON with sed (no jq dependency — see CLAUDE.md § 7 M2 and § 9).
_phase_06_resolve_ref() {
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
