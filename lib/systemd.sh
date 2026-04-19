#!/usr/bin/env bash
# mangos-installer — systemd unit installation and lifecycle
# SPDX-License-Identifier: GPL-2.0-only
# See CLAUDE.md for design, README.md for usage
# shellcheck shell=bash
#
# Stub for milestone 1. Real implementation lands in milestone 3 (phase 13)
# and will install templates from templates/, run daemon-reload, and
# enable/start per-realm units.

systemd_unimplemented() {
  log_error "lib/systemd.sh is a stub; systemd helpers land in milestone 3"
  return 1
}
