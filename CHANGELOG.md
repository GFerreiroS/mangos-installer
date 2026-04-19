# Changelog

All notable changes to mangos-installer are recorded in this file.

The project follows the milestone plan in `CLAUDE.md`. Each milestone is a working slice of the spec; partial work is not released.

## Unreleased

_(no work in flight)_

## 0.1.0-alpha — Milestone 1 (2026-04-19)

First scaffold. Bootstrap fetches the installer, runs phase 0 interactively, then walks through stub messages for phases 1–14.

### Added

- Repository scaffold: `install.sh`, `phases/`, `flows/`, `lib/`, `templates/`, `docs/`, GPL-2.0 license, `.shellcheckrc`, GitHub Actions workflow that runs `shellcheck -x` on every push and pull request.
- Bootstrap entrypoint (`install.sh`):
  - Root, bash version (≥ 5.0), `curl`, and `tar` sanity checks.
  - Re-attaches stdin to `/dev/tty` when piped through `curl ... | sudo bash` so prompts work.
  - Inline distro/arch sanity (Ubuntu 22.04 / 24.04 / Debian 12; x86_64 / aarch64) before any network fetch.
  - Fetches `mangos-installer-${INSTALLER_VERSION}.tar.gz` from GitHub releases with fallback to the `main` branch tarball; extracts to `/tmp/mangos-installer-$$/`.
  - `--dev-mode` flag skips the fetch and uses the local checkout.
  - `exec`s into `phases/runner.sh` with environment pre-populated.
- Phase dispatcher (`phases/runner.sh`) that loads all libraries and dispatches to the requested flow.
- Fresh-install flow (`flows/fresh-install.sh`) that walks phase 0 through phase 14.
- Library modules:
  - `lib/constants.sh` — installer-wide constants (URLs, supported distros/archs, OpenSSL sidecar version + SHA256, fallback refs).
  - `lib/log.sh` — leveled logging to a file with timestamps and phase context, plus `die`.
  - `lib/ui.sh` — terminal output (colors, Unicode/ASCII fallback, status lines, prompts for text/yes-no/choice/password).
  - `lib/state.sh` — phase completion tracking against a state file.
  - `lib/config.sh` — flat env-style config file with atomic writes (`config_load/get/set`).
  - `lib/secrets.sh` — root-owned (0600) credentials file.
  - `lib/platform.sh` — OS, arch, RAM, and disk detection.
  - `lib/privilege.sh` — root checks and a `run_as_mangos` wrapper.
  - `lib/download.sh` — `curl` wrappers with retry/resume, background download with PID + exit-code tracking, and protocol validation.
  - `lib/archive.sh` — multi-format detection and extraction (tar.gz / tar.xz / tar.bz2 / zip / 7z / rar).
  - `lib/cores.sh` — per-core configuration (only `zero` recognised; one/two/three rejected with a clear message).
  - `lib/gamedata.sh`, `lib/db.sh`, `lib/systemd.sh` — stubs for later milestones.
- Phase 0 (`phases/phase-00-preflight.sh`) — fully implemented:
  - System checks (root, OS, arch, RAM, disk, network).
  - Realm prompts (core, internal name, display name, address, world port).
  - Database prompts (local with generated password, or remote with admin credentials).
  - Gamedata source prompt (local path, URL with protocol validation + background download, or manual).
  - Persists answers to `config.env` and credentials to `/etc/mangos-installer/secrets.env`.
  - Marks the phase complete in the state file.
- Phase 1–14 stubs that print a `not implemented yet` message and mark themselves complete.
- Flow stubs for `add-realm`, `update-realm`, `uninstall-realm`, `uninstall-all`, and `resume` (all currently exit with a clear message; full implementations land in milestone 4).
- Systemd unit templates (`templates/mangos-realmd.service`, `templates/mangos-mangosd@.service`) committed for milestone 3 use.
- Documentation: `README.md`, `docs/ARCHITECTURE.md`, `docs/MANUAL-TESTING.md`, `docs/UPSTREAM-DIFFS.md`.

### Known limitations

- During milestone 1 the mangos user does not yet exist (phase 1 is a stub), so config and state are written to `/var/tmp/mangos-installer-bootstrap/` rather than the final `~mangos/mangos/.installer/` location. Phase 1 will migrate them in milestone 2.
- The bootstrap log lives at `/tmp/mangos-installer-$$-boot.log`; phase 1 will migrate it once the install root exists.
- Stub phases mark themselves complete in the state file. After a milestone bump, run `state_reset` (or wipe `/var/tmp/mangos-installer-bootstrap/state/`) before re-running so the new implementations are not skipped. Schema-version handling is planned for milestone 5.
