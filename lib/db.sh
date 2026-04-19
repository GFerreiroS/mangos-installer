#!/usr/bin/env bash
# mangos-installer — MariaDB / MySQL helpers
# SPDX-License-Identifier: GPL-2.0-only
# See CLAUDE.md for design, README.md for usage
# shellcheck shell=bash
#
# Stub for milestone 1. Real implementation lands in milestone 2 (phases
# 5 and 7). Will wrap mysql / mariadb client invocations, version
# detection, schema application, and grant verification.

db_unimplemented() {
  log_error "lib/db.sh is a stub; DB helpers land in milestone 2"
  return 1
}
