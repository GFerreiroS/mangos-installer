# Architecture

High-level summary. For the complete specification (every design decision, every phase, every gotcha), see `CLAUDE.md` at the repository root.

## Execution model

```
curl -fsSL .../install.sh | sudo bash
          │
          ▼
    install.sh (bootstrap, ~200 lines, self-contained)
      ├─ sanity: root, bash 5.0+, curl, tar
      ├─ re-attach stdin from /dev/tty (if piped)
      ├─ inline OS + arch checks
      ├─ fetch mangos-installer-<ver>.tar.gz from GitHub
      │    (or use local checkout with --dev-mode)
      └─ exec phases/runner.sh
          │
          ▼
    phases/runner.sh
      ├─ source lib/*.sh in dependency order
      ├─ wire MANGOS_LOG_FILE / _CONFIG_FILE / _SECRETS_FILE / _STATE_FILE
      ├─ config_load (resumes prior answers)
      └─ dispatch to flows/<MANGOS_FLOW>.sh
          │
          ▼
    flows/fresh-install.sh (default)
      └─ for phase in phase-00 … phase-14: run_phase_NN
```

Each phase is an idempotent function `run_phase_NN` that:

1. Sets `MANGOS_CURRENT_PHASE` for log context.
2. Short-circuits via `state_has_completed` if it has already finished.
3. Prints a header (`ui_phase_header`), then status lines (`ui_status_ok` / `_info` / `_warn` / `_fail`).
4. Calls `state_mark_complete` at the end, or `die` on failure.

## Two-tier state

| Scope      | File                                                   | Phases used |
|------------|--------------------------------------------------------|-------------|
| Global     | `~mangos/mangos/.installer/state/global.state`         | 0–5         |
| Per-realm  | `~mangos/mangos/.installer/state/<realm>.state`        | 6–14        |

Each line: `<phase-name> completed <ISO-8601-UTC>`.

During milestone 1 the mangos user does not yet exist, so state lives in `/var/tmp/mangos-installer-bootstrap/state/global.state`. Phase 1 will migrate it in milestone 2.

## Configuration split

| File                                         | Owner       | Mode | Contents                                    |
|----------------------------------------------|-------------|------|---------------------------------------------|
| `~mangos/mangos/.installer/config.env`       | `mangos`    | 0644 | realm names, paths, DB mode/host/port/user  |
| `/etc/mangos-installer/secrets.env`          | `root:root` | 0600 | DB admin password, SFTP password, etc.      |
| `<realm>/etc/mangosd.conf`, `realmd.conf`    | `mangos`    | 0640 | runtime config consumed by the server       |

`config.env` is flat `KEY="value"` pairs — sourceable as bash but parseable by hand. No YAML, no `yq`/`jq` dependency.

## Directory layout on host

```
/home/mangos/mangos/
├── opt/openssl-1.1/            # sidecar; does NOT replace system OpenSSL
├── .installer/                 # config, state, logs, state.json
├── <realm>/
│   ├── source/                 # git clone of mangoszero/server
│   ├── database/               # git clone of mangoszero/database
│   ├── build/                  # cmake build
│   ├── bin/                    # installed mangosd, realmd
│   ├── etc/                    # mangosd.conf, realmd.conf (0640)
│   ├── gamedata/               # dbc/, maps/, mmaps/, vmaps/
│   ├── logs/                   # runtime (also goes to journald)
│   └── backups/                # DB dumps before updates
└── ...

/etc/mangos-installer/secrets.env        # 0600 root:root
/etc/systemd/system/mangos-realmd.service
/etc/systemd/system/mangos-mangosd@.service
```

Multiple realms on one host share a single `mangos-realmd` (auth daemon on port 3724). Each realm gets its own `mangos-mangosd@<realm>` instance via the systemd template unit.

## Design principles

- **Idempotent phases.** Re-running a completed phase is a no-op via the state guard.
- **No system mutation beyond the absolutely necessary.** The system's OpenSSL stays intact; system GCC stays intact (we pass `-DCMAKE_C_COMPILER=gcc-11` explicitly instead of `update-alternatives`); no implicit `apt upgrade`.
- **Minimal terminal output; verbose log.** One line per sub-step on the terminal, full detail in `install-YYYYMMDD-HHMMSS.log`. `NO_COLOR` and `TERM=dumb` respected.
- **Non-interactive-ready from the start.** Every `ui_prompt_*` helper reads `$MANGOS_<VAR>` under `MANGOS_NONINTERACTIVE=1`, so milestone 4's flag-driven mode needs no refactor.
- **No hidden dependencies.** `jq` is optional; `yq` is banned; `shellcheck -x` is CI-enforced.

## Divergences from upstream guides

See `docs/UPSTREAM-DIFFS.md`. In short: we sidecar OpenSSL 1.1 rather than replacing the system binary; we pass the GCC-11 compiler path explicitly rather than using `update-alternatives`; we run `mysql` directly rather than driving the upstream `InstallDatabase.sh` with `expect`; we use systemd template units rather than the `screen`-based `wowadmin.sh` approach.
