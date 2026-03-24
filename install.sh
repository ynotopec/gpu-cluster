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

METALLB_RANGE="${METALLB_RANGE:-${1:-}}"

exec "${ROOT_DIR}/scripts/install_cluster.sh" "${METALLB_RANGE}"
