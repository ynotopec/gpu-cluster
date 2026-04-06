#!/usr/bin/env bash
set -euo pipefail

log() {
  printf '[%s] %s\n' "$(date -u +'%Y-%m-%dT%H:%M:%SZ')" "$*"
}

die() {
  log "ERROR: $*"
  exit 1
}

require_root() {
  if [[ "$(id -u)" -ne 0 ]]; then
    die "This script must be run as root."
  fi
}

ensure_command() {
  local cmd="$1"
  command -v "$cmd" >/dev/null 2>&1 || die "Missing required command: $cmd"
}

install_if_missing() {
  local package="$1"
  local binary="${2:-$1}"

  if command -v "$binary" >/dev/null 2>&1; then
    return 0
  fi

  if command -v apt-get >/dev/null 2>&1; then
    DEBIAN_FRONTEND=noninteractive apt-get update -y >/dev/null
    DEBIAN_FRONTEND=noninteractive apt-get install -y "$package" >/dev/null
  elif command -v yum >/dev/null 2>&1; then
    yum install -y "$package" >/dev/null
  else
    die "Could not install '$package' automatically (no apt-get/yum)."
  fi

  command -v "$binary" >/dev/null 2>&1 || die "Installed '$package' but '$binary' still not found."
}
