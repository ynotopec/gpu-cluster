#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"

users_list="${1:-${usersList:-}}"

usage() {
  cat <<USAGE
Usage:
  sudo KUBECONFIG=/home/admin/.kube/config ./scripts/fix_admin.sh $'alice\\nbob'
USAGE
}

admin_group() {
  if [[ -f /etc/debian_version ]]; then
    echo sudo
  elif [[ -f /etc/redhat-release ]]; then
    echo wheel
  else
    echo sudo
  fi
}

grant_user_access() {
  local user_login="$1"
  local group="$2"
  local user_home

  usermod -aG "${group}" "${user_login}" || true
  user_home="$(getent passwd "${user_login}" | cut -d: -f6)"
  [[ -z "${user_home}" ]] && return 0

  kubectl config set-context --current --namespace="home-${user_login}" >/dev/null
  install -d -m 700 "${user_home}/.kube"
  kubectl config view --raw >"${user_home}/.kube/config"
  chown -R "${user_login}:${user_login}" "${user_home}/.kube"

  if command -v oc >/dev/null 2>&1; then
    oc adm policy add-scc-to-user privileged -z default -n "home-${user_login}" >/dev/null 2>&1 || true
  fi
}

main() {
  require_root

  if [[ -z "${users_list}" ]]; then
    usage
    die "No users provided."
  fi

  [[ -n "${KUBECONFIG:-}" ]] || die "KUBECONFIG is required."
  [[ -f "${KUBECONFIG}" ]] || die "KUBECONFIG points to missing file: ${KUBECONFIG}"
  ensure_command kubectl

  local backup_config="${HOME}/.kubeconfig.bck"
  cp "${KUBECONFIG}" "${backup_config}"
  trap 'cp "${backup_config}" "${KUBECONFIG}"' EXIT

  local group
  group="$(admin_group)"

  while IFS= read -r user_login; do
    [[ -z "${user_login}" ]] && continue
    grant_user_access "${user_login}" "${group}"
  done <<<"${users_list}"

  log "Admin access reconciliation complete."
}

main "$@"
