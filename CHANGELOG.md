# Changelog

All notable changes to mangos-installer are recorded in this file.

The project follows the milestone plan in `CLAUDE.md`. Each milestone is a working slice of the spec; partial work is not released.

## Unreleased

_(no work in flight)_

## 0.3.0-alpha — Milestone 3 (2026-04-20)

End-to-end fresh install now works. All 14 phases are real: the installer walks from a blank Ubuntu/Debian to `systemctl is-active mangos-mangosd@zero` returning `active`, with ports 3724 (auth) and 8085 (world) open. A machine-readable `state.json` is kept fresh after every phase so external tools can observe progress without tailing logs.

### Added

- `lib/gamedata.sh` replaces the milestone-1 stubs. `gamedata_find_data_dir` walks up to 4 levels under the user-provided path looking for `Data/common.MPQ`; `gamedata_validate_structure` checks the required MPQ set for the selected core (`zero` = common, common-2, patch, patch-2, patch-3) and rejects `expansion.MPQ` / `lichking.MPQ` when core is `zero`; `gamedata_move_to_realm` renames (or copies on cross-fs) `Data/` into `<realm>/gamedata/Data`; `gamedata_extract_products_exist` checks for populated `dbc/`, `maps/`, `vmaps/`, `mmaps/` output dirs (used by phase 12's idempotence guard).
- `lib/systemd.sh` replaces the milestone-1 stub. `systemd_install_units` copies `templates/mangos-*.service` into `/etc/systemd/system/` only when they differ (cmp-based) and runs `daemon-reload` only when something actually changed. `systemd_have` distinguishes "systemctl binary present" from "system manager is alive" so Docker-without-systemd fails fast and loudly. `systemd_wait_port <port> <timeout>` polls `ss` (or `netstat` as a fallback) for a listening socket.
- `lib/state.sh` gains `state_list_realms` (derives realm names from `REALM_<name>_CORE=` keys), `state_json_write` (atomic, printf-based, no `jq` dependency — matches the schema in CLAUDE.md § 5.7), and the private helpers `_state_json_escape` and `_state_realm_file`. `awk ... -- <file>` is replaced with `awk '...' <file>` throughout (awk does not accept `--` as an end-of-options marker; the old invocation silently emitted empty `completed_phases` arrays).
- `phase-11-gamedata-prep` — branches on the `GAMEDATA_SOURCE` persisted by phase 0. `path`: validates the user's directory and moves `Data/` into the realm. `url`: blocks on `download_wait` for the background curl kicked off by phase 0, runs `archive_extract` on the download, validates, and moves. `manual`: writes an empty `Data/` dir plus instructions and exits 0 without marking the phase complete — subsequent runs return to phase 11 and validate the placed files before proceeding.
- `phase-12-gamedata-extract` — invokes `map-extractor`, `vmap-extractor` (+ `vmap_assembler` if the build produced one), and `mmaps_generator` directly in the realm's `gamedata/` directory as the mangos user. Each runs backgrounded with a 60-second heartbeat so operators can see the phase is alive during the 30 min–2 h runtime. Chooses the first matching binary from a set of casing variants (`map-extractor` / `MapExtractor`, etc.) because upstream has renamed them across releases. After extraction, removes the extractor binaries and helper scripts — they are not needed at runtime and clutter the realm's gamedata dir.
- `phase-13-systemd` — `systemd_install_units` + `systemctl enable mangos-realmd` + `systemctl enable mangos-mangosd@<realm>`. Does not start services; start is phase 14.
- `phase-14-smoke` — starts `mangos-realmd`, waits up to 15 s for port 3724 to open, then starts `mangos-mangosd@<realm>` and waits up to 120 s for the world port. On any failure pulls the last 50 lines of `journalctl -u <unit>` into the log and dies with a clear pointer to the journal. Updates `REALM_<name>_STATUS=installed` and `LAST_UPDATED` on success. Prints the final success banner with the realm name, display name, external address + ports, the systemctl / journalctl commands for operation, the `state.json` path, the installer log path, and a loud warning to change the default `ADMINISTRATOR/ADMINISTRATOR` accounts before exposing the server.
- `flows/fresh-install.sh` — calls `state_json_write` after every phase. Phase 14's banner replaces the previous closing message.

### Decisions recorded

- **Phase 12 invokes extractor binaries directly** rather than drive `ExtractResources.sh` with `expect`. The individual extractors (`map-extractor`, `vmap-extractor`, `mmaps_generator`) accept non-interactive invocation; wrapping the shell script would add an `expect` dependency and a brittle dialogue match for no gain. Documented in `docs/UPSTREAM-DIFFS.md`.

### Known limitations

- `state_json_write` regenerates `state.json` from config + state files on every call; there is no writer coordination across multiple concurrent installer runs. If you run two installers against the same install root at the same time, the last writer wins. The installer was never designed for that case.
- Phase 14's port-open check only confirms the daemons are binding. It does not exercise the auth or world protocols; a runtime crash immediately after port-open would still trip the second `systemd_is_active` check but a subtle protocol problem would slip through. A real client handshake test is a candidate for milestone 5.
- If the operator quits during `phase-12-gamedata-extract`, partial `dbc/maps/vmaps/mmaps` directories may remain. The idempotence guard checks only for presence and non-emptiness, so a kill-during-extraction followed by a re-run skips the phase. Delete the partial output dirs before re-running if this happens.

## 0.2.0-alpha — Milestone 2 (2026-04-20)

Phases 1–10 are now real implementations: the installer creates the mangos user, installs apt dependencies, builds the OpenSSL 1.1 sidecar, ensures gcc-11 is available, sets up MariaDB, clones the upstream repos at the latest release tag, applies DB schemas, builds mangosd/realmd, installs the binaries, and writes runtime configs. Phases 11–14 (gamedata prep/extract, systemd, smoke test) remain stubs and land in milestone 3.

After milestone 2, `~/mangos/zero/bin/mangosd --version` and `realmd --version` work, the three databases are populated, and `~/mangos/zero/etc/{mangosd,realmd}.conf` contain valid connection strings. The daemons do not yet start under systemd — that is milestone 3.

### Added

- `lib/db.sh` — real MariaDB/MySQL client wrapper (`db_exec_root`, `db_exec_admin`, `db_import_admin`, `db_version`, `db_exists`, `db_table_exists`, `db_wait_ready`). Passwords travel via `MYSQL_PWD` rather than argv.
- `lib/platform.sh` gains `platform_build_parallelism` — picks `-j` based on RAM (≥8GB full `nproc`, 4–8GB half, else 2).
- `lib/privilege.sh` gains `run_script_as_mangos` and `mangos_user_exists`.
- `lib/config.sh` gains `config_hydrate_realm <name>` — copies `REALM_<name>_<suffix>` values into stable `MANGOS_REALM_<suffix>` globals so per-realm phases can address realm data without knowing the basename.
- `lib/state.sh` gains `state_switch_to_realm` / `state_switch_to_global`.
- `phases/runner.sh` re-hydrates `MANGOS_REALM_*` from `MANGOS_CURRENT_REALM` after `config_load` so phases past 0 have realm vars set on resume.
- `phase-01-user-and-dirs` — `useradd -m mangos`, scaffolds the `$MANGOS_ROOT/{opt,.installer/{logs,state,build-cache},<realm>/{source,database,build,bin,etc,gamedata,logs,backups}}` tree, migrates the boot log / `config.env` / state file out of `/var/tmp/mangos-installer-bootstrap` into `.installer/`, and writes a fresh `global.state` that preserves only the `phase-00` marker (drops M1-stub markers for 2–14). Self-heals if the state says "done" but the install root doesn't exist.
- `phase-02-apt-deps` — single non-interactive `apt-get install` with baked-in community fixes (`libreadline-dev`, `liblua5.2-dev`, `default-libmysqlclient-dev`). `mariadb-server` is added only in `DB_MODE=local`; `unrar`/`p7zip-full` are deferred to `archive.sh`'s on-demand install in phase 11.
- `phase-03-openssl-sidecar` — downloads `openssl-1.1.1w.tar.gz`, verifies SHA256, extracts, and builds with `LDFLAGS=-Wl,-rpath,$OPENSSL_PREFIX/lib` so resulting libs carry the sidecar in rpath. System OpenSSL 3 is left untouched.
- `phase-04-gcc-available` — `apt install gcc-11 g++-11` if absent; records `MANGOS_CC`/`MANGOS_CXX` in `config.env`. System default gcc stays intact (no `update-alternatives`).
- `phase-05-mariadb` — local (`systemctl enable --now mariadb`, drop test DB + anonymous users, `CREATE USER` / `GRANT ALL ON *.* … WITH GRANT OPTION` via `unix_socket`) and remote (version-check `MariaDB 10.3+` / `MySQL 5.7+`/`8.x`, `SHOW GRANTS` verification).
- `phase-06-fetch-sources` — GitHub API ref resolution via `sed` (no `jq`), fallback to `MANGOS_FALLBACK_REF`. `git clone --recursive` or fetch+checkout as the mangos user.
- `phase-07-db-schemas` — creates the three databases, applies `Setup/` → `Full_DB/` (world) → `Updates/` SQL files from the upstream database repo, then `UPDATE realmlist` id=1. Marker-table checks skip already-populated DBs.
- `phase-08-build` — CMake with explicit compiler + OpenSSL paths + per-core flags from `core_cmake_flags`; `cmake --build` with auto-tuned `-j`; `cmake --install` into `<build>/install/`.
- `phase-09-install-binaries` — copies `mangosd`/`realmd` into `<realm>/bin` and `*-extractor`/`*.sh`/`offmesh.txt` into `<realm>/gamedata`.
- `phase-10-configs` — copies every `*.conf.dist` from `install/etc/` to `<realm>/etc/` without the `.dist`, then `sed`-injects `LoginDatabaseInfo` / `WorldDatabaseInfo` / `CharacterDatabaseInfo` / `DataDir` / `LogsDir` / `WorldServerPort` into `mangosd.conf` and `LoginDatabaseInfo` / `RealmServerPort` / `LogsDir` into `realmd.conf`. `Warden.Enabled=0`. Files end up `0640 mangos:mangos`.
- `flows/fresh-install.sh` runs phases 1–5 against `global.state`, then `state_switch_to_realm` before phases 6–14.

### Known limitations

- Phase 7's update-SQL files are applied once on first run; later re-runs of phase 7 (after a state wipe) may fail on already-applied updates. A marker table (`_installer_db_version`) is planned for milestone 4's update flow.
- The realmlist `UPDATE` assumes a row with `id=1` exists after the Realm setup SQL. If the upstream schema changes its initial seeding, operators will need to `INSERT` id=1 manually (the phase warns).
- Phase 10 overwrites any manual edits to runtime `.conf` files whenever it re-runs. Treat `config.env` as the source of truth.
- DB passwords travel in `mangosd.conf` / `realmd.conf` as part of the semicolon-delimited connection string, so the password must not contain `;`. Phase 0's generated passwords are alphanumeric; remote-mode operators must avoid `;` themselves.
- The sidecar OpenSSL tarball is fetched straight from `openssl.org`; this is a single point of failure for the build. A mirror fallback is a candidate for milestone 5.

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
