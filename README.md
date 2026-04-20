# mangos-installer

[![shellcheck](https://github.com/GFerreiroS/mangos-installer/actions/workflows/shellcheck.yml/badge.svg)](https://github.com/GFerreiroS/mangos-installer/actions/workflows/shellcheck.yml)
[![license: GPL-2.0](https://img.shields.io/badge/license-GPL--2.0-blue.svg)](LICENSE)

Single-command installer for [MaNGOS Zero](https://github.com/mangoszero/server) — a World of Warcraft 1.12.x private server emulator. Replaces the [manual installation walkthrough](https://www.getmangos.eu/wiki/documentation/installation-guides/guideslinux/installing-mangos-on-ubuntu-server-2204-r40014/) with one command and a single phase-0 conversation:

```bash
curl -fsSL https://raw.githubusercontent.com/GFerreiroS/mangos-installer/main/install.sh | sudo bash
```

The installer handles OS detection, apt dependencies, an OpenSSL 1.1 sidecar build (rpath-wired — the system OpenSSL stays intact), gcc-11 pinned at CMake time, MariaDB setup (or remote-DB validation), upstream source fetching at the latest release tag, CMake build, database schema application with migration tracking, MPQ extraction, and systemd services. Multiple realms on one host are supported via systemd template units.

## Status

**1.0.0** — feature-complete for the MaNGOS Zero scope. All five milestones from `CLAUDE.md` are delivered. See `CHANGELOG.md`.

## Supported environments

| Distro         | Architecture     | Status    | Notes |
|----------------|------------------|-----------|-------|
| Ubuntu 22.04   | x86_64, aarch64  | supported |       |
| Ubuntu 24.04   | x86_64, aarch64  | supported |       |
| Debian 12      | x86_64, aarch64  | supported |       |
| Ubuntu 20.04 / 23.10 / 25.04 | any | untested (warn) | proceed with `--force-unsupported` |
| Debian 11 / 13 | any | untested (warn) | proceed with `--force-unsupported` |
| Anything else  | any | refused   | no Fedora, Arch, Alpine, Windows, macOS |

`x86_64` and `aarch64` are the only supported architectures. 32-bit / armv7 / riscv64 are explicitly refused.

## Supported cores

| Core | Expansion | Status |
|------|-----------|--------|
| zero | Vanilla 1.12.x | supported |
| one | TBC 2.4.3 | stub (see `lib/cores.sh` for porting checklist) |
| two | WotLK 3.3.5 | stub |
| three | Cataclysm 4.3.4 | stub (needs CASC, not MPQ) |

## Usage

### One-line install (production)

```bash
curl -fsSL https://raw.githubusercontent.com/GFerreiroS/mangos-installer/main/install.sh | sudo bash
```

### Download-and-review install

```bash
curl -fsSLO https://raw.githubusercontent.com/GFerreiroS/mangos-installer/main/install.sh
less install.sh
sudo bash install.sh
```

### Local-clone dev install

```bash
git clone https://github.com/GFerreiroS/mangos-installer.git
cd mangos-installer
sudo bash install.sh --dev-mode
```

`--dev-mode` skips the GitHub tarball fetch and uses the working tree.

### Non-interactive install

Every prompt has a matching `--flag`:

```bash
sudo bash install.sh --non-interactive \
  --core=zero \
  --realm-name=zero --realm-display-name="My Realm" \
  --realm-address=server.example.com --realm-world-port=8085 \
  --db-mode=local \
  --gamedata-source=path --gamedata-path=/srv/wow-1.12.3 \
  --yes
```

`install.sh --help` prints the full flag list.

### Management actions

Re-running the installer on an existing host automatically shows a menu. Pick the action there, or invoke directly:

```bash
sudo bash install.sh --flow=add-realm        # add an additional realm
sudo bash install.sh --flow=update-realm     # pull latest upstream, rebuild, with rollback
sudo bash install.sh --flow=uninstall-realm  # remove one realm, preserve backups
sudo bash install.sh --flow=uninstall-all    # full teardown
sudo bash install.sh --flow=resume           # resume after Ctrl-C / kill / crash
```

## What the installer creates

```
/home/mangos/mangos/
├── opt/openssl-1.1/            # OpenSSL 1.1 sidecar (rpath-wired)
├── .installer/
│   ├── config.env              # flat KEY="value", human-editable
│   ├── secrets.env (-> /etc/…) # not here; see below
│   ├── state.json              # machine-readable snapshot, schema v1
│   ├── state/{global,<realm>}.state
│   └── logs/install-*.log
├── zero/                       # realm "zero"
│   ├── source/ database/ build/ bin/ etc/
│   ├── gamedata/ (Data/ dbc/ maps/ vmaps/ mmaps/)
│   ├── logs/
│   └── backups/
└── …

/etc/mangos-installer/
└── secrets.env                 # 0600 root:root — DB passwords

/etc/systemd/system/
├── mangos-realmd.service       # global auth daemon (port 3724)
└── mangos-mangosd@.service     # template, instantiated per realm
```

Default ports: `3724` for auth (one per host), `8085+N` for world (one per realm).

## Documentation

- `CLAUDE.md` — full specification (design decisions, every phase, every gotcha).
- `docs/ARCHITECTURE.md` — high-level summary linking back to `CLAUDE.md`.
- `docs/MANUAL-TESTING.md` — per-milestone test procedures.
- `docs/UPSTREAM-DIFFS.md` — where and why this installer diverges from the upstream community guide.
- `CHANGELOG.md` — what each milestone added.

## Troubleshooting

Common failure modes are listed in each relevant phase's `die` call with concrete next steps. The three you are most likely to hit:

- **Port 3724 or world port already in use.** Phase 0 warns; another process is bound. `sudo ss -lntp sport = :3724` to find it.
- **OpenSSL build fails on aarch64 with low RAM.** The OpenSSL 1.1 build picks `-j` from `platform_build_parallelism`; on <4 GB RAM boards the default of 2 is still too much. Re-run with `MANGOS_BUILD_PARALLEL=1` (or wait — it eventually succeeds even under memory pressure).
- **Mangos build runs out of disk.** Phase 8 now pre-checks for 6 GB free at the realm dir. Reclaim with `docker system prune` / `apt clean`, then `--flow=resume`.

Full log: `/home/mangos/mangos/.installer/logs/install-*.log`. Service logs: `journalctl -u mangos-realmd` / `journalctl -u mangos-mangosd@<realm>`.

## Repository owner setup

Before publishing a release, update `lib/constants.sh`:

- `INSTALLER_REPO_URL` / `INSTALLER_RAW_URL` / `INSTALLER_TARBALL_URL` — currently `GFerreiroS/mangos-installer`; change if you fork.
- `INSTALLER_VERSION` — bump per release; the bootstrap looks for the matching tarball tag.
- `MANGOS_FALLBACK_REF` — MaNGOS Zero release tag used when the GitHub API is unreachable. Bump when you have tested against a newer upstream release.

Tag the release (`git tag vX.Y.Z && git push --tags`) so the pinned tarball URL resolves.

## Contributing

1. Run `shellcheck -x` on every touched file before opening a PR; the GitHub Actions workflow will also enforce it.
2. Work milestone-by-milestone: each milestone is a working slice of the spec.
3. Commit one logical chunk at a time with descriptive messages (`phase-XX: <what>` or `milestone Y: <summary>`).
4. Test per `docs/MANUAL-TESTING.md` before claiming the milestone is done.
5. Record decisions that diverge from the upstream guide in `docs/UPSTREAM-DIFFS.md`.

Proposing upstream adoption is a milestone-5 goal; see `CLAUDE.md` § 7 M5 for the plan.

## Demo

An asciinema recording of a happy-path install will live at `docs/demo.cast` when one is produced. Recommended command for whoever records it:

```bash
asciinema rec docs/demo.cast -c 'sudo bash install.sh --dev-mode --non-interactive --core=zero \
  --realm-name=demo --realm-display-name=Demo --realm-address=127.0.0.1 --db-mode=local \
  --gamedata-source=path --gamedata-path=/srv/wow-client --yes' -t 'mangos-installer demo'
```

## License

GPL-2.0 — matches upstream MaNGOS. See `LICENSE`.

## Acknowledgements

Builds on:

- [MaNGOS Zero](https://github.com/mangoszero/server) — the upstream emulator.
- The MaNGOS community installation guide (Aviscall01's Ubuntu 22.04 walkthrough) — the structural template for the phase layout.
- Forum community fixes baked in and credited in `docs/UPSTREAM-DIFFS.md`: rogical (GCC 11 pin), z932074 (OpenSSL sidecar coexistence pattern), Cr10 (`libreadline-dev`), silentlabber (`liblua5.2-dev`), xFreeway (container-testing inspiration).
