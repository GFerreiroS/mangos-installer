# Manual testing

Per-milestone procedures. Setting up the test environment (VMs or LXC/Incus containers) is out of scope here — see the separate `mangos-installer-tests` harness repo for that.

Quick reminder: if you are iterating on the installer from a local checkout, run it with `--dev-mode` to skip the GitHub tarball fetch:

```bash
sudo bash install.sh --dev-mode
```

## Milestone 1 — bootstrap + phase 0 + phase 1–14 stubs

### Prerequisites
- Ubuntu 22.04 / 24.04 or Debian 12 container / VM
- Architecture x86_64 or aarch64
- Network access to github.com, raw.githubusercontent.com (piped mode)

### Run
```bash
# Piped (production path):
curl -fsSL https://raw.githubusercontent.com/GFerreiroS/mangos-installer/main/install.sh | sudo bash

# Or, against a local clone:
sudo bash install.sh --dev-mode
```

### What you should see

1. Bootstrap prints `[OK]` for sanity, OS, and arch.
2. Phase 0 header: `→ preflight  [0/14]`.
3. System-check status lines:
   - `✓ architecture: x86_64` (or `aarch64`)
   - `✓ OS: ubuntu 24.04` (or similar)
   - `✓ RAM: NGB`
   - `✓ disk free at /home: NGB`
   - `✓ network: GitHub reachable`
4. Interactive prompts in this order:
   - **MaNGOS core** — choose `zero` (any other choice aborts with `not yet implemented`).
   - **Realm internal name** — default `zero`. Lowercase identifier; invalid input aborts.
   - **Realm display name** — default `My Vanilla Realm`.
   - **Realm address** — default detected from `ip route`, falls back to `127.0.0.1`.
   - **World port** — default `8085`; 1024–65535 range enforced.
   - **Database mode** — `local` or `remote`.
     - `local`: generated 24-char password shown once in bold.
     - `remote`: prompts for host / port / admin user / admin password (silent input).
   - **Gamedata source** — `path` / `url` / `manual`.
     - `path`: absolute path accepted; validation is stubbed to succeed in M1.
     - `url`: protocol-checked; `http`/`ftp` warns and requires confirmation; background download starts and its PID is printed.
     - `manual`: no action; phase 11 will instruct placement later.
5. `✓ preflight complete` and then 14 stub phase headers roll through, each printing a one-line `stub: ... — milestone 2|3` note and advancing.
6. Final banner: `milestone 1 complete: phase 0 + 14 stubs walked`, followed by paths of config, secrets, state, and log.

### Artifacts to verify

```bash
# Config (mangos-readable once the real install root exists; in M1 lives here):
ls -l /var/tmp/mangos-installer-bootstrap/config.env
cat  /var/tmp/mangos-installer-bootstrap/config.env

# Secrets (root-only):
ls -l /etc/mangos-installer/secrets.env   # should be -rw------- root root
sudo cat /etc/mangos-installer/secrets.env

# State (phase-00 should be marked complete, plus the 14 stubs):
ls -l /var/tmp/mangos-installer-bootstrap/state/global.state
cat  /var/tmp/mangos-installer-bootstrap/state/global.state

# Boot log — verbose log of the whole run:
ls -l /tmp/mangos-installer-*-boot.log
less /tmp/mangos-installer-*-boot.log
```

Expected state file contents (order by completion time):
```
phase-00-preflight completed 2026-04-19T...
phase-01-user-and-dirs completed 2026-04-19T...
phase-02-apt-deps completed 2026-04-19T...
... through phase-14-smoke
```

### Checks to run

- [ ] Re-run the installer. Phase 0 should short-circuit with `preflight already complete; reusing previous answers`, and each stub should print `... (already done — skipping)` thanks to the state guard.
- [ ] Wipe state and re-run to exercise the fresh path:
  ```bash
  sudo rm -rf /var/tmp/mangos-installer-bootstrap /etc/mangos-installer
  sudo bash install.sh --dev-mode
  ```
- [ ] Abort mid-prompt with Ctrl-C; verify nothing catastrophic and boot log captures the interruption.
- [ ] Try each gamedata source branch (path / url / manual).
- [ ] For URL: point at `http://example.com/anything.zip` to exercise the insecure-protocol warning. Answer `no` — installer should exit cleanly with `aborted by user`.
- [ ] Confirm `secrets.env` is `0600 root:root` and `config.env` is readable by mangos (or the current user, in M1 before phase 1 runs).
- [ ] Confirm no secret values are written into the boot log (`grep DB_ADMIN_PASSWORD /tmp/mangos-installer-*-boot.log` should show the *name* only, not the value).
- [ ] CI: push a throwaway branch; the `shellcheck` GitHub Actions workflow should run and pass.

### Known M1 caveats
- All 14 stub phases mark themselves complete. After pulling milestone 2, wipe `/var/tmp/mangos-installer-bootstrap/state/` before re-running, otherwise the new real implementations will be skipped.
- The background download in URL mode is orphaned to `init` once the installer exits, since phase 11 (which would consume it) is a stub in M1. Kill any leftover `curl` PID manually if you tested this path.

## Milestone 2 — core install path

### What works after M2
Phases 1–10 are real: the installer creates the mangos user, installs apt deps, builds the OpenSSL 1.1 sidecar, installs gcc-11, sets up MariaDB, clones the upstream repos, applies DB schemas, builds mangosd/realmd, installs the binaries, and writes runtime configs. Services do NOT start yet — that is milestone 3 (phases 11–14).

### Prerequisites
- Ubuntu 22.04 / 24.04 or Debian 12 container / VM with internet access.
- At least 4GB RAM and 20GB free disk for the build. 8GB RAM is preferable — the build uses full `nproc` above that threshold.
- If you tested M1 in the same container, wipe the bootstrap staging before running M2 so the stub completion markers don't skip the real work. Phase 1 self-heals if the mangos user is missing, but clearing state is cleaner:
  ```bash
  sudo rm -rf /var/tmp/mangos-installer-bootstrap
  ```

### Run (local gamedata mode — the fast path for M2 acceptance)

```bash
cd /path/to/mangos-installer
sudo bash install.sh --dev-mode
```

Answer the prompts (core `zero`, your realm name, `local` DB mode, gamedata source `manual` — gamedata doesn't matter for M2, phases 11–14 are still stubs).

Expect the run to take 20–60 minutes on x86_64, 45–120 minutes on aarch64:
- Phase 1 (user + dirs): < 1s.
- Phase 2 (apt): 30–90s depending on apt mirror and what's already cached.
- Phase 3 (OpenSSL): 5–15 min.
- Phase 4 (gcc): 10–60s (often a no-op if gcc-11 is already installed).
- Phase 5 (MariaDB): 5–20s.
- Phase 6 (fetch sources): 30s–2 min.
- Phase 7 (DB schemas): 10s–2 min (world data dump is the slow part).
- Phase 8 (build): 15–40 min (the longest phase).
- Phase 9 (install binaries): < 5s.
- Phase 10 (configs): < 1s.

### Verify binaries exist and report a version

```bash
sudo -u mangos /home/mangos/mangos/zero/bin/mangosd --version
sudo -u mangos /home/mangos/mangos/zero/bin/realmd --version
```

Both should print a MaNGOS build string. If they segfault with a library error, the OpenSSL sidecar rpath is wrong — capture `ldd /home/mangos/mangos/zero/bin/mangosd | grep -E 'ssl|crypto'` and check it resolves to `/home/mangos/mangos/opt/openssl-1.1/lib/lib*.so.1.1`.

### Verify the DBs are populated

```bash
sudo mariadb -e "SHOW DATABASES LIKE 'mangos%'"
sudo mariadb mangos_auth  -e "SELECT id,name,address,port FROM realmlist"
sudo mariadb mangos_world0 -e "SELECT COUNT(*) FROM creature_template"
sudo mariadb mangos_character0 -e "SHOW TABLES LIKE 'characters'"
```

Realmlist should have id=1 with the display name / address / port you chose. `creature_template` count should be in the tens of thousands (populated by Full_DB).

### Verify config strings are injected

```bash
sudo grep -E '^(LoginDatabaseInfo|WorldDatabaseInfo|CharacterDatabaseInfo|DataDir|LogsDir|WorldServerPort|Warden.Enabled)' \
  /home/mangos/mangos/zero/etc/mangosd.conf

sudo grep -E '^(LoginDatabaseInfo|RealmServerPort|LogsDir)' \
  /home/mangos/mangos/zero/etc/realmd.conf

ls -l /home/mangos/mangos/zero/etc/
```

All four connection strings should read `host;port;user;<pw>;dbname`. Perms should be `-rw-r----- mangos mangos`.

### Idempotence check

Re-run the installer without wiping state. Every phase should print `(already done — skipping)`. No network fetches, no compilation.

```bash
sudo bash install.sh --dev-mode
```

### Remote DB path (optional)

```bash
sudo bash install.sh --dev-mode
# answer MANGOS_DB_MODE=remote, give host/port/admin-user/admin-password
```

Phase 5 will `SELECT VERSION()`, version-check against the support matrix, and `SHOW GRANTS FOR CURRENT_USER`. Missing `CREATE/DROP/SELECT/…` aborts the phase.

### Troubleshooting
- **OpenSSL SHA256 mismatch** — only plausible if openssl.org served a mirror with a corrupt tarball; re-run will re-download.
- **`build did not produce mangosd`** — compilation failure; look near the end of `/home/mangos/mangos/.installer/logs/install-*.log` for the real error, usually a specific source file.
- **`realmlist UPDATE failed`** — the upstream schema's initial row is missing or numbered differently; insert id=1 manually.

## Milestone 3 — _planned_

## Milestone 3 — _planned_
See `CLAUDE.md` § 7 Milestone 3.

## Milestone 4 — _planned_
See `CLAUDE.md` § 7 Milestone 4.

## Milestone 5 — _planned_
See `CLAUDE.md` § 7 Milestone 5.
