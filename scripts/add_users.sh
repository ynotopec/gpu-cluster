#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"

users_list="${1:-}"
users_ssh="${2:-}"

usage() {
  cat <<USAGE
Usage:
  sudo USER_PASSWORD='StrongPass' ./scripts/add_users.sh $'alice\\nbob' 'ssh-ed25519 AAAA...'
USAGE
}

generate_password() {
  if command -v openssl >/dev/null 2>&1; then
    openssl rand -base64 18 | tr -c '[:alnum:]' '+'
  else
    install_if_missing openssl openssl
    openssl rand -base64 18 | tr -c '[:alnum:]' '+'
  fi
}

create_user() {
  local user_login="$1"
  local password="$2"

  if getent passwd "${user_login}" >/dev/null 2>&1; then
    log "User exists, skipping: ${user_login}"
    return 0
  fi

  useradd --create-home --shell /bin/bash "${user_login}"
  echo "${user_login}:${password}" | chpasswd
  passwd --expire "${user_login}" || true

  if [[ -d /etc/skel ]]; then
    install_if_missing rsync rsync
    rsync -aAX /etc/skel/ "/home/${user_login}/" || true
  fi

  if [[ -n "${users_ssh}" ]]; then
    install -d -m 700 "/home/${user_login}/.ssh"
    printf '%s\n' "${users_ssh}" >>"/home/${user_login}/.ssh/authorized_keys"
    chmod 600 "/home/${user_login}/.ssh/authorized_keys"
  fi

  chown -R "${user_login}:${user_login}" "/home/${user_login}"
}

main() {
  require_root

  if [[ -z "${users_list}" ]]; then
    usage
    die "No users provided."
  fi

  local password="${USER_PASSWORD:-$(generate_password)}"
  if [[ -z "${USER_PASSWORD:-}" ]]; then
    log "Generated password for new users: ${password}"
  fi

  while IFS= read -r user_login; do
    [[ -z "${user_login}" ]] && continue
    create_user "${user_login}" "${password}"
  done <<<"${users_list}"

  log "User provisioning complete."
}

main "$@"
