#!/usr/bin/env bash
# mangos-installer — terminal UI (status lines, prompts, color/Unicode handling)
# SPDX-License-Identifier: GPL-2.0-only
# See CLAUDE.md for design, README.md for usage
# shellcheck shell=bash
#
# All UI output goes to stderr so stdout stays clean for return values from
# ui_prompt_* helpers. Honors NO_COLOR and TERM=dumb. ASCII fallback when
# Unicode would not render (TERM=dumb or POSIX locale or MANGOS_ASCII=1).

_ui_use_color() {
  [[ -z "${NO_COLOR:-}" ]] && [[ -t 2 ]] && [[ "${TERM:-dumb}" != "dumb" ]]
}

_ui_use_unicode() {
  [[ "${TERM:-dumb}" != "dumb" ]] \
    && [[ "${MANGOS_ASCII:-0}" != "1" ]] \
    && [[ "${LANG:-en_US.UTF-8}" != *POSIX* ]] \
    && [[ "${LANG:-en_US.UTF-8}" != C ]]
}

_ui_color() {
  _ui_use_color || return 0
  case "$1" in
    green)  printf '\033[32m' ;;
    red)    printf '\033[31m' ;;
    yellow) printf '\033[33m' ;;
    blue)   printf '\033[34m' ;;
    dim)    printf '\033[2m'  ;;
    bold)   printf '\033[1m'  ;;
    reset)  printf '\033[0m'  ;;
  esac
}

_ui_sym() {
  if _ui_use_unicode; then
    case "$1" in
      ok)    printf '✓' ;;
      fail)  printf '✗' ;;
      warn)  printf '⚠' ;;
      info)  printf 'ℹ' ;;
      arrow) printf '→' ;;
    esac
  else
    case "$1" in
      ok)    printf '[OK]'   ;;
      fail)  printf '[FAIL]' ;;
      warn)  printf '[!]'    ;;
      info)  printf '[i]'    ;;
      arrow) printf '->'     ;;
    esac
  fi
}

ui_print_banner() {
  printf '\n%s%s%s\n\n' "$(_ui_color bold)" "$1" "$(_ui_color reset)" >&2
}

ui_phase_header() {
  local num="$1" total="$2" name="$3"
  printf '\n%s%s%s %s  [%d/%d]\n' \
    "$(_ui_color blue)" "$(_ui_sym arrow)" "$(_ui_color reset)" \
    "$name" "$num" "$total" >&2
  log_info "=== Phase ${num}/${total}: ${name} ==="
}

ui_status_ok() {
  printf '  %s%s%s %s\n' "$(_ui_color green)" "$(_ui_sym ok)" "$(_ui_color reset)" "$1" >&2
  log_info "OK: $1"
}

ui_status_fail() {
  printf '  %s%s%s %s\n' "$(_ui_color red)" "$(_ui_sym fail)" "$(_ui_color reset)" "$1" >&2
  log_error "FAIL: $1"
}

ui_status_warn() {
  printf '  %s%s%s %s\n' "$(_ui_color yellow)" "$(_ui_sym warn)" "$(_ui_color reset)" "$1" >&2
  log_warn "$1"
}

ui_status_info() {
  printf '  %s%s%s %s\n' "$(_ui_color dim)" "$(_ui_sym info)" "$(_ui_color reset)" "$1" >&2
  log_info "$1"
}

ui_print_recent_log() {
  local lines="${1:-20}"
  local lf="${MANGOS_LOG_FILE:-}"
  [[ -n "$lf" ]] && [[ -f "$lf" ]] || return 0
  printf '\n%slast %d log lines from %s:%s\n' \
    "$(_ui_color dim)" "$lines" "$lf" "$(_ui_color reset)" >&2
  tail -n "$lines" -- "$lf" >&2 || true
  printf '\nfull log: %s\n' "$lf" >&2
}

# ui_prompt_text <question> <default> <env_var_name>
# Returns the answer on stdout. In non-interactive mode reads from $env_var.
ui_prompt_text() {
  local question="$1" default="$2" env_var="$3"
  if [[ "${MANGOS_NONINTERACTIVE:-0}" == "1" ]]; then
    local val="${!env_var:-$default}"
    [[ -z "$val" ]] && die "non-interactive mode but $env_var not set (and no default)"
    log_info "non-interactive answer for $env_var: $val"
    printf '%s\n' "$val"
    return 0
  fi
  local prompt
  if [[ -n "$default" ]]; then prompt="$question [$default]: "
  else                          prompt="$question: "
  fi
  local answer
  while :; do
    read -rp "$prompt" answer
    answer="${answer:-$default}"
    [[ -n "$answer" ]] && break
    printf 'value cannot be empty.\n' >&2
  done
  log_info "answer for $env_var: $answer"
  printf '%s\n' "$answer"
}

# ui_prompt_yes_no <question> <default(yes|no)> [env_var_name]
# Exit code: 0 = yes, 1 = no.
ui_prompt_yes_no() {
  local question="$1" default="$2" env_var="${3:-}"
  if [[ "${MANGOS_NONINTERACTIVE:-0}" == "1" ]]; then
    local val=""
    [[ -n "$env_var" ]] && val="${!env_var:-}"
    val="${val:-$default}"
    case "${val,,}" in
      yes|y|true|1)  return 0 ;;
      no|n|false|0)  return 1 ;;
      *) die "non-interactive: ${env_var:-(no env var)} has invalid value '$val' (need yes/no)" ;;
    esac
  fi
  local hint
  if [[ "${default,,}" == "yes" ]]; then hint="[Y/n]"; else hint="[y/N]"; fi
  local answer
  while :; do
    read -rp "$question $hint: " answer
    answer="${answer:-$default}"
    case "${answer,,}" in
      yes|y) return 0 ;;
      no|n)  return 1 ;;
      *)     printf 'please answer y or n.\n' >&2 ;;
    esac
  done
}

# ui_prompt_choice <question> <default> <env_var_name> <option1> [option2 ...]
ui_prompt_choice() {
  local question="$1" default="$2" env_var="$3"
  shift 3
  local options=( "$@" )
  if [[ "${MANGOS_NONINTERACTIVE:-0}" == "1" ]]; then
    local val="${!env_var:-$default}"
    local o
    for o in "${options[@]}"; do
      [[ "$o" == "$val" ]] && { log_info "non-interactive answer for $env_var: $val"; printf '%s\n' "$val"; return 0; }
    done
    die "non-interactive: $env_var='$val' not in [${options[*]}]"
  fi
  local opts_str
  opts_str=$(printf '%s|' "${options[@]}")
  opts_str="${opts_str%|}"
  local answer
  while :; do
    read -rp "$question ($opts_str) [$default]: " answer
    answer="${answer:-$default}"
    local o
    for o in "${options[@]}"; do
      [[ "$o" == "$answer" ]] && { log_info "answer for $env_var: $answer"; printf '%s\n' "$answer"; return 0; }
    done
    printf 'invalid choice. pick one of: %s\n' "$opts_str" >&2
  done
}

# ui_prompt_password <question> <env_var_name>
ui_prompt_password() {
  local question="$1" env_var="$2"
  if [[ "${MANGOS_NONINTERACTIVE:-0}" == "1" ]]; then
    local val="${!env_var:-}"
    [[ -z "$val" ]] && die "non-interactive: $env_var not set"
    printf '%s\n' "$val"
    return 0
  fi
  local pw
  while :; do
    read -rsp "$question: " pw
    printf '\n' >&2
    [[ -n "$pw" ]] && break
    printf 'password cannot be empty.\n' >&2
  done
  printf '%s\n' "$pw"
}
