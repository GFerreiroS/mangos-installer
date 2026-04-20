# Upstream divergences

Where and why mangos-installer diverges from the MaNGOS community's standard installation paths (primarily the Ubuntu 22.04 community guide and the upstream `InstallDatabase.sh`).

Each divergence has a **what** (the change), a **why** (the incident or constraint it resolves), and optionally a **follow-up** (how to propose it back to upstream).

## Locked-in divergences

_The OpenSSL sidecar, gcc-11 CMake pin, and direct-mysql DB bootstrap are implemented as of milestone 2. The systemd switch lands in milestone 3. Each decision is fixed; contributors should not silently revert._

### OpenSSL 1.1 as a sidecar, not a system replacement

- **What.** Build OpenSSL 1.1.1w from source into `/home/mangos/mangos/opt/openssl-1.1/` with `rpath` wired into the resulting libraries. Link mangosd/realmd against it via explicit CMake flags:
  ```
  -DOPENSSL_ROOT_DIR=…/opt/openssl-1.1
  -DOPENSSL_INCLUDE_DIR=…/opt/openssl-1.1/include
  -DOPENSSL_CRYPTO_LIBRARY=…/opt/openssl-1.1/lib/libcrypto.so.1.1
  -DOPENSSL_SSL_LIBRARY=…/opt/openssl-1.1/lib/libssl.so.1.1
  ```
  Do **not** overwrite `/usr/bin/openssl` or drop a `.conf` into `/etc/ld.so.conf.d/`.
- **Why.** The WoW client protocol uses algorithms removed in OpenSSL 3; mangos needs 1.1. Upstream guides have historically replaced the system OpenSSL, which breaks `apt`, `curl`, SSH host-key fingerprinting, and other system tools. A sidecar keeps the system toolchain intact.

### GCC 11 via explicit CMake compiler, not `update-alternatives`

- **What.** On systems where the default GCC is 12+, `apt install gcc-11 g++-11` but do **not** register it with `update-alternatives`. Invoke the build with `-DCMAKE_C_COMPILER=gcc-11 -DCMAKE_CXX_COMPILER=g++-11`.
- **Why.** `update-alternatives --set gcc gcc-11` globally changes the default for every other package built on the host. The forum guide does this and then forgets to document unwinding it. Pinning compilers at the CMake level keeps the side-effects local to the mangos build.

### Direct `mysql` calls instead of driving `InstallDatabase.sh` with `expect`

- **What.** Re-implement the database bootstrap: create the three databases (`mangos_auth`, `mangos_character<N>`, `mangos_world<N>`), apply the schema SQL and world data dump from the `mangoszero/database` repo in the right order, run any dated updates, and update the realmlist row via plain `mysql -e`.
- **Why.** `InstallDatabase.sh` is an interactive menu-driven shell script. Driving it with `expect` is fragile (any wording change breaks the match); re-implementing the handful of steps directly is shorter, faster, and easier to test. A side benefit is that remote-DB mode becomes clean to support.
- **Follow-up.** Propose upstream break `InstallDatabase.sh` into a non-interactive `apply-database.sh` that accepts the same arguments. Then this installer can delegate to that script and the two paths converge.

### systemd unit + template instance, not `screen` / `wowadmin.sh`

- **What.** Install `mangos-realmd.service` (one global auth daemon) plus `mangos-mangosd@.service` (template, instantiated per realm). Use `systemctl` for start/stop/status. Runtime logs go to the journal.
- **Why.** `wowadmin.sh`, the community management wrapper, runs the servers inside detached `screen` sessions. Those are invisible to the host's process supervisor, do not restart on crash, do not aggregate logs, and do not integrate with boot. systemd gives you restart-on-failure, boot-time startup, per-unit logs, resource limits, and hardening (`NoNewPrivileges`, `ProtectSystem=strict`, etc.) for free.

### Warden disabled by default

- **What.** Inject `Warden.Enabled = 0` into the generated `mangosd.conf`.
- **Why.** Blizzard's anti-cheat has known compatibility problems with OpenSSL variants; leaving it on with the sidecar has historically caused startup crashes or runtime hangs on certain realms. Operators who want Warden can flip the flag back on manually; defaults stay on the safe path.
- **Follow-up.** Revisit once upstream confirms the sidecar is compatible with Warden across the supported distros.

### No `yq` / `jq` as hard dependencies

- **What.** `config.env` is flat `KEY="value"` pairs (sourceable from bash). `state.json` is generated with `printf`/heredocs, not `jq`. If a later milestone genuinely needs to *read* JSON (e.g., to edit `state.json` in-place), it may install `jq` conditionally at that point.
- **Why.** Every additional dependency is another thing that can be missing, version-skewed, or behave differently across distros. Flat key-value + printf covers milestone 1–3 comfortably.

### No auto `apt upgrade`

- **What.** The installer runs `apt-get update` and a single targeted `apt-get install`. It does **not** `apt-get upgrade` the host.
- **Why.** Upgrading unrelated system packages mid-install is surprising and occasionally destructive (kernel updates requiring reboots, behavior changes in other services). The installer touches only what it needs.

## Open questions not yet resolved

These will be decided when the relevant milestone lands and will get their own sections here:

- **Gamedata extractor interaction** — milestone 3 will choose between driving `ExtractResources.sh` with `expect` or invoking the underlying extractor binaries directly with flags. The decision depends on how complex the wrapper's logic turns out to be when read end-to-end.
- **DB update tracking** — milestone 4's update flow needs a way to know which dated patches under `database/Updates/` have already been applied. If the upstream repo has a marker convention we will use it; otherwise we will add our own marker table.
- **Port allocation for multi-realm** — milestone 4 will either auto-pick the next free world port starting at 8085 or refuse to start if 8085 is taken.

## Community fixes baked in

The following items from forum threads on the upstream community guide are applied automatically by this installer; credits are preserved in the top of the relevant phase or lib where the fix lives:

- `libreadline-dev` added to the dependency list (Cr10) — implemented in phase 2.
- `liblua5.2-dev` in the dependency list so the Lua-scripting linkage resolves (silentlabber) — implemented in phase 2.
- GCC 11 pinned at CMake time rather than via `update-alternatives` (rogical) — implemented in phase 4 (installed) and phase 8 (pinned at configure time).
- OpenSSL 1.1 as a sidecar rather than replacing the system binary (z932074's coexistence pattern) — implemented in phase 3.
