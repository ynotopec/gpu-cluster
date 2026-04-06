#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/lib/env.sh
source "${ROOT_DIR}/scripts/lib/env.sh"

load_repo_env
METALLB_RANGE="${METALLB_RANGE:-${1:-}}"

exec "${ROOT_DIR}/scripts/install_cluster.sh" "${METALLB_RANGE}"
