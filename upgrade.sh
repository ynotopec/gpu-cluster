#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="${ROOT_DIR}/.env"

if [[ -f "${ENV_FILE}" ]]; then
  # shellcheck disable=SC1090
  set -a
  source "${ENV_FILE}"
  set +a
fi

if [[ "$(id -u)" -ne 0 ]]; then
  echo "This script must be run as root." >&2
  exit 1
fi

if command -v apt-get >/dev/null 2>&1; then
  DEBIAN_FRONTEND=noninteractive apt-get update -y
  DEBIAN_FRONTEND=noninteractive apt-get upgrade -y
fi

if command -v snap >/dev/null 2>&1; then
  snap refresh
fi

exec "${ROOT_DIR}/scripts/install_cluster.sh" "${METALLB_RANGE:-}"
