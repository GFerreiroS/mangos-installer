# mangos-installer

Single-command installer for [MaNGOS Zero](https://github.com/mangoszero/server) — a World of Warcraft 1.12.x private server emulator. Replaces the manual installation walkthrough with one command:

```bash
curl -fsSL https://raw.githubusercontent.com/GFerreiroS/mangos-installer/main/install.sh | sudo bash
```

The installer handles: OS detection, package installation, OpenSSL 1.1 sidecar build, GCC version pinning, MariaDB setup, source fetching, CMake build, gamedata extraction, config generation, and systemd service setup. It supports multiple realms on one host via systemd template units.

> **Status:** alpha — milestone 1 only. Phase 0 (preflight + interactive configuration) is functional; subsequent phases print `not implemented yet` placeholders. See `CHANGELOG.md` for what each milestone adds.

## Supported environments

| Distro       | Architecture     | Status    |
|--------------|------------------|-----------|
| Ubuntu 22.04 | x86_64, aarch64  | supported |
| Ubuntu 24.04 | x86_64, aarch64  | supported |
| Debian 12    | x86_64, aarch64  | supported |
| Other        | —                | refused   |

`x86_64` and `aarch64` are the only supported architectures. 32-bit and other architectures are explicitly rejected.

## Usage

### One-line install (recommended once published)

```bash
curl -fsSL https://raw.githubusercontent.com/GFerreiroS/mangos-installer/main/install.sh | sudo bash
```

### Download-and-review install

```bash
curl -fsSLO https://raw.githubusercontent.com/GFerreiroS/mangos-installer/main/install.sh
less install.sh
sudo bash install.sh
```

### Local development

```bash
git clone https://github.com/GFerreiroS/mangos-installer.git
cd mangos-installer
sudo bash install.sh --dev-mode
```

`--dev-mode` skips the tarball fetch and uses the local checkout.

### Non-interactive (planned for milestone 4)

```bash
sudo MANGOS_NONINTERACTIVE=1 \
     MANGOS_REALM_CORE=zero \
     MANGOS_DB_MODE=local \
     MANGOS_GAMEDATA_SOURCE=path \
     MANGOS_GAMEDATA_PATH=/srv/wow-1.12.3 \
     bash install.sh
```

The infrastructure is wired in milestone 1; the per-flag CLI lands in milestone 4.

## What the installer creates

```
/home/mangos/mangos/
├── opt/openssl-1.1/        # OpenSSL 1.1 sidecar (does NOT replace system OpenSSL)
├── .installer/             # config, state, logs
├── zero/                   # realm "zero" (multi-realm via systemd templates)
│   ├── source/  build/  bin/  etc/  gamedata/  logs/  backups/
│   └── ...
└── ...

/etc/mangos-installer/
└── secrets.env             # 0600 root:root — DB credentials, etc.

/etc/systemd/system/
├── mangos-realmd.service       # global auth daemon
└── mangos-mangosd@.service     # template unit, instantiated per realm
```

Default ports: `3724` (auth, shared across realms), `8085+N` (world, per realm).

## Project layout

| Path             | Purpose                                                  |
|------------------|----------------------------------------------------------|
| `install.sh`     | bootstrap entrypoint; sanity checks, fetch, hand off     |
| `phases/`        | numbered phases (00–14), one per installation step       |
| `flows/`         | orchestrators that sequence phases for each operation    |
| `lib/`           | shared helpers (logging, UI, state, config, downloads…)  |
| `templates/`     | systemd unit files                                       |
| `docs/`          | architecture, manual testing, upstream divergences       |

`CLAUDE.md` is the complete design specification; `docs/ARCHITECTURE.md` is the high-level summary.

## Configuration for repository owners

Before publishing a release, update the values in `lib/constants.sh`:

- `INSTALLER_REPO_URL`, `INSTALLER_RAW_URL`, `INSTALLER_TARBALL_URL` — currently set to `GFerreiroS/mangos-installer`. Change if you fork.
- `INSTALLER_VERSION` — bump per release. The bootstrap looks for the matching tarball tag on GitHub.
- `MANGOS_FALLBACK_REF` — pinned MaNGOS Zero release tag used when the GitHub API is unreachable.

## License

GPL-2.0 — matches upstream MaNGOS. See `LICENSE`.

## Acknowledgements

- [MaNGOS Zero](https://github.com/mangoszero/server) — upstream emulator.
- The MaNGOS community installation guides and forum threads, whose accumulated fixes are baked into this installer. Specific divergences and credits are documented in `docs/UPSTREAM-DIFFS.md`.
