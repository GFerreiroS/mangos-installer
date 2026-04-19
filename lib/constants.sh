#!/usr/bin/env bash
# mangos-installer — installer-wide constants
# SPDX-License-Identifier: GPL-2.0-only
# See CLAUDE.md for design, README.md for usage
# shellcheck shell=bash

# --- Repository (update on fork) ---
readonly INSTALLER_REPO_URL="https://github.com/GFerreiroS/mangos-installer"
readonly INSTALLER_RAW_URL="https://raw.githubusercontent.com/GFerreiroS/mangos-installer"
readonly INSTALLER_TARBALL_URL="https://github.com/GFerreiroS/mangos-installer/archive/refs/tags"
readonly INSTALLER_TARBALL_MAIN="https://github.com/GFerreiroS/mangos-installer/archive/refs/heads/main.tar.gz"
readonly INSTALLER_VERSION="0.1.0-alpha"

# --- Upstream MaNGOS ---
readonly MANGOS_ZERO_REPO="https://github.com/mangoszero/server"
readonly MANGOS_ZERO_DB_REPO="https://github.com/mangoszero/database"
readonly MANGOS_ZERO_RELEASES_API="https://api.github.com/repos/mangoszero/server/releases/latest"

# --- OpenSSL sidecar ---
readonly OPENSSL_SIDECAR_VERSION="1.1.1w"
readonly OPENSSL_SIDECAR_URL="https://www.openssl.org/source/openssl-1.1.1w.tar.gz"
readonly OPENSSL_SIDECAR_SHA256="cf3098950cb4d853ad95c0841f1f9c6d3dc102dccfcacd521d93925208b76ac8"

# --- Supported environments ---
readonly SUPPORTED_DISTROS=( "ubuntu:22.04" "ubuntu:24.04" "debian:12" )
readonly WARN_DISTROS=( "ubuntu:20.04" "ubuntu:23.10" "ubuntu:25.04" "debian:11" "debian:13" )
readonly SUPPORTED_ARCHS=( "x86_64" "aarch64" )

# --- Fallback MaNGOS ref when GitHub API is unreachable ---
readonly MANGOS_FALLBACK_REF="v22.04.181"

# --- Bash version requirement ---
readonly MIN_BASH_MAJOR=5
readonly MIN_BASH_MINOR=0

# --- Default install root and bootstrap staging ---
# During milestone 1 the mangos user does not yet exist (phase 1 is a stub),
# so config and state live in /var/tmp until phase 1 migrates them.
readonly MANGOS_DEFAULT_USER="mangos"
readonly MANGOS_DEFAULT_INSTALL_ROOT="/home/mangos/mangos"
readonly MANGOS_BOOTSTRAP_STAGING="/var/tmp/mangos-installer-bootstrap"
readonly MANGOS_SECRETS_DIR="/etc/mangos-installer"
