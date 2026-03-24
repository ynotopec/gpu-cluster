#!/usr/bin/env bash
set -euo pipefail

load_repo_env() {
  local script_dir repo_root env_file
  script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  repo_root="$(cd "${script_dir}/../.." && pwd)"
  env_file="${repo_root}/.env"

  if [[ -f "${env_file}" ]]; then
    # shellcheck disable=SC1090
    set -a
    source "${env_file}"
    set +a
  fi
}
