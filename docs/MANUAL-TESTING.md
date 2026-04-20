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

## Milestone 3 — end-to-end install

After M3 the installer walks from blank OS to `systemctl is-active mangos-mangosd@zero` → `active`. This is the full acceptance path and requires a real WoW 1.12.x client.

### Prerequisites
- Ubuntu 22.04 / 24.04 or Debian 12 environment with **real systemd** (Incus / LXC container or a VM, not vanilla Docker). `phase-13-systemd` fails loudly under Docker-without-systemd.
- 4 GB+ RAM, 30 GB+ free disk (extracted `maps/`, `vmaps/`, `mmaps/` are ~8 GB combined).
- A WoW 1.12.x client directory with the MPQ set (see `CLAUDE.md` § 5 for the expected files).
- If you tested M1 or M2 in the same environment, wipe stale state first:
  ```bash
  sudo systemctl stop mangos-mangosd@zero mangos-realmd 2>/dev/null
  sudo rm -rf /home/mangos/mangos /var/tmp/mangos-installer-bootstrap
  sudo userdel -r mangos 2>/dev/null
  ```

### Incus quick path

```bash
incus launch images:ubuntu/24.04 mangos-m3
incus file push -r /path/to/mangos-installer/. mangos-m3/root/mangos-installer/
incus file push -r /path/to/wow-client-1.12.3/. mangos-m3/srv/wow-client/
incus exec mangos-m3 -- bash -c 'apt-get update && apt-get install -y curl ca-certificates sudo'
incus exec mangos-m3 -- bash -c 'cd /root/mangos-installer && bash install.sh --dev-mode'
```

At the gamedata prompt, pick `path` and enter `/srv/wow-client` (or wherever you pushed the client).

### Expected runtime

| Phase | x86_64 (modern) | aarch64 |
|---|---|---|
| 0–10 (M2 path) | 25–60 min | 50–120 min |
| 11 (gamedata prep — path mode) | < 5 s | < 5 s |
| 11 (url mode, depends on link speed) | n × MB/s | n × MB/s |
| 12 (gamedata extract) | 30–60 min | 60–180 min |
| 13 (systemd) | < 2 s | < 2 s |
| 14 (smoke) | 5–120 s | 5–120 s |

Phase 12 is where most of the new-time lives; the heartbeat prints every 60 seconds so the phase looks alive.

### Acceptance checks

```bash
incus exec mangos-m3 -- bash -c '
  set -e
  systemctl is-active mangos-realmd                 # active
  systemctl is-active mangos-mangosd@zero           # active
  ss -lnt sport = :3724 | tail -n +2                # LISTEN
  ss -lnt sport = :8085 | tail -n +2                # LISTEN
  ls /home/mangos/mangos/zero/gamedata/             # dbc/ maps/ mmaps/ vmaps/ Data/
  jq .realms[0].status /home/mangos/mangos/.installer/state.json  # "installed"
'
```

All six checks should succeed. `jq` is not a hard dependency but handy for the last check; `cat` works too.

### Connect a real client

Set your WoW 1.12.x client's `realmlist.wtf` to `set realmlist <incus-container-ip>`, then launch. The default `ADMINISTRATOR / ADMINISTRATOR` account lets you log in; change the password immediately inside the game with `.account set password <old> <new> <new>`.

### Failure diagnostics

If phase 14 fails, the installer dumps the last 50 lines of `journalctl` for the failing unit and dies. For more:

```bash
incus exec mangos-m3 -- journalctl -u mangos-realmd --no-pager
incus exec mangos-m3 -- journalctl -u mangos-mangosd@zero --no-pager
incus exec mangos-m3 -- tail -200 /home/mangos/mangos/.installer/logs/install-*.log
```

Common failure modes:
- **realmd exits with libssl error** — phase 3 or 8 miswired the OpenSSL rpath. `ldd /home/mangos/mangos/zero/bin/realmd | grep ssl` should resolve to `/home/mangos/mangos/opt/openssl-1.1/lib/libssl.so.1.1`.
- **mangosd hangs on port 8085** — the world server is still loading the database and gamedata into memory; the 120-second timeout may be too tight on slow aarch64 boards. Increase `TimeoutStartSec` in the template or accept that the first boot is slow and restart.
- **`gamedata missing required MPQs`** — the client you pointed at is TBC / WotLK / corrupt. The installer refuses TBC+ MPQs when `core=zero`.
- **`mmaps_generator` runs forever** — normal. The mmap phase single-threads per tile; a 16-core machine speeds up by having more tiles in flight but each tile is still a long arithmetic grind. Leave it alone.

### Milestone 3 idempotence

Re-run the installer after a successful M3 install. Every phase should print `(already done — skipping)`; phase 14's guard additionally verifies services are still active and re-prints the success banner.

## Milestone 4 — lifecycle management

All tests below assume an Incus container with M3 already passing (realm "zero" installed, services running). If you are starting from a clean host, run M3 first or use `--non-interactive` with the flags below.

### Non-interactive fresh install (scriptable end-to-end)

```bash
sudo bash install.sh --dev-mode --non-interactive \
  --core=zero \
  --realm-name=zero --realm-display-name="Test" \
  --realm-address=127.0.0.1 --realm-world-port=8085 \
  --db-mode=local \
  --gamedata-source=path --gamedata-path=/srv/wow-client \
  --yes
```

Expected: no prompts, straight through phases 0–14, same success banner as an interactive run.

### Re-run shows menu

With a completed install:

```bash
sudo bash install.sh --dev-mode
```

Expect the banner `mangos installer … — management` followed by a realm inventory and a 1–6 choice prompt. Pick `6) exit` to confirm clean exit.

### Add a second realm

```bash
sudo bash install.sh --dev-mode --flow=add-realm
```

Answer: core `zero`, realm name `alt`, accept defaults for display / address, accept the suggested port 8086. Phase 6 clones upstream into `/home/mangos/mangos/alt/source`; phase 8 rebuilds; phase 12 re-extracts (⚠ 30 min–2 h). To skip extraction, stop at phase 12's first heartbeat and:

```bash
sudo -u mangos bash -c 'cd /home/mangos/mangos/alt/gamedata && \
  ln -s ../../zero/gamedata/Data Data && \
  ln -s ../../zero/gamedata/dbc dbc && \
  ln -s ../../zero/gamedata/maps maps && \
  ln -s ../../zero/gamedata/vmaps vmaps && \
  ln -s ../../zero/gamedata/mmaps mmaps'
sudo bash install.sh --dev-mode --flow=resume
```

The resume flow skips completed phases; the products check in `gamedata_extract_products_exist` sees the symlinked outputs and phase 12 completes instantly.

Acceptance: after `add-realm` finishes, `systemctl status mangos-mangosd@alt` is active, `ss -lnt sport = :8086` shows LISTEN, and `cat /home/mangos/mangos/.installer/state.json` shows both realms.

### Update a realm

```bash
sudo bash install.sh --dev-mode --flow=update-realm
```

If the installed ref matches `MANGOS_FALLBACK_REF` / latest, the flow will say "already on latest" and ask if you want to force a rebuild. Accept. Pre-update backups land in `/home/mangos/mangos/zero/backups/pre-update-<ts>-*.sql.gz`; the git tag `installer-pre-update-<ts>` is written to the source checkout; phases 6/8/9/10 re-run; DB Updates are re-applied; smoke test re-runs.

Test the rollback path by deliberately breaking the build:

```bash
sudo -u mangos sh -c 'echo "#error intentional break" >> /home/mangos/mangos/zero/source/src/mangosd/Main.cpp'
sudo bash install.sh --dev-mode --flow=update-realm
```

Expected: phase 8 fails; the ERR trap prints `update FAILED — rolling back` and restores source + DBs; world service restarts.

### Uninstall a realm

```bash
sudo bash install.sh --dev-mode --flow=uninstall-realm
```

Pick `alt` (the second realm) and type `alt` to confirm. The flow takes a final backup, stops the unit, drops the character + world DBs, and removes everything under `/home/mangos/mangos/alt/` except `backups/`. The auth DB stays (still used by the primary realm).

Verify:

```bash
sudo mariadb -e "SHOW DATABASES LIKE 'mangos%'"  # mangos_character0, mangos_world0, mangos_auth only
ls /home/mangos/mangos/alt/                       # only backups/
ls /home/mangos/mangos/alt/backups/               # final-<ts>-*.sql.gz present
systemctl status mangos-mangosd@alt               # inactive (dead), disabled
```

### Uninstall everything

```bash
sudo bash install.sh --dev-mode --flow=uninstall-all
```

Type `YES` (uppercase) to confirm. The flow loops each remaining realm, removes systemd units, removes secrets, and prompts separately about deleting the mangos user. Decline the user removal first to verify backups are preserved under `/home/mangos/mangos/<realm>/backups/`. Re-run and accept the user removal to verify the full teardown.

### Resume after kill

Start a fresh install:

```bash
sudo bash install.sh --dev-mode --non-interactive \
  --core=zero --realm-name=zero --realm-display-name="Test" \
  --realm-address=127.0.0.1 --db-mode=local \
  --gamedata-source=path --gamedata-path=/srv/wow-client \
  --yes &
INSTALL_PID=$!

# Kill it during phase 8 (build):
sleep 300 && kill -KILL $INSTALL_PID

# Resume:
sudo bash install.sh --dev-mode --flow=resume
```

Expected: phases 0–7 show `(already done — skipping)`; phase 8 restarts cleanly (CMake incremental build picks up where it left off).

### Fully non-interactive add-realm + update

```bash
sudo bash install.sh --dev-mode --non-interactive --flow=add-realm \
  --core=zero --realm-name=pvp --realm-display-name="PvP" \
  --realm-address=127.0.0.1 --realm-world-port=8087

sudo bash install.sh --dev-mode --non-interactive --flow=update-realm \
  --yes
  # (update takes the single installed realm if MANGOS_UPDATE_REALM unset)
```

Each command should succeed without any prompts.

## Milestone 5 — _planned_
See `CLAUDE.md` § 7 Milestone 5.
