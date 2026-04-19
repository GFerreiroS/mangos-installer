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

## Milestone 2 — _planned_
See `CLAUDE.md` § 7 Milestone 2.

## Milestone 3 — _planned_
See `CLAUDE.md` § 7 Milestone 3.

## Milestone 4 — _planned_
See `CLAUDE.md` § 7 Milestone 4.

## Milestone 5 — _planned_
See `CLAUDE.md` § 7 Milestone 5.
