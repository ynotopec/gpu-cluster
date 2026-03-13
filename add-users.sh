#!/usr/bin/env bash
set -euo pipefail

users_list="${1:-}"
users_ssh="${2:-}"

if [ -z "${users_list}" ]; then
  echo "No users provided. Pass newline-separated users as argument 1."
  exit 0
fi

if command -v mkpasswd >/dev/null 2>&1; then
  generated_password="$(mkpasswd | tr -c '[:alnum:]' '+')"
else
  generated_password="$(openssl rand -base64 18 | tr -c '[:alnum:]' '+')"
fi
password="${USER_PASSWORD:-${generated_password}}"

install_rsync() {
  apt-get update -y >/dev/null 2>&1 && apt-get install -y rsync >/dev/null 2>&1 && return 0
  yum install -y rsync >/dev/null 2>&1 && return 0
  echo "Unable to install rsync automatically."
  return 1
}

install_rsync || true

echo "Provisioning users..."
echo "${users_list}" | while IFS= read -r user_login; do
  [ -z "${user_login}" ] && continue

  if getent passwd "${user_login}" >/dev/null 2>&1; then
    continue
  fi

  useradd "${user_login}" --shell /bin/bash
  echo "${user_login}:${password}" | chpasswd
  passwd --expire "${user_login}" || true

  if [ -d /etc/skel ]; then
    rsync -aAX /etc/skel/ "/home/${user_login}/" 2>/dev/null || true
  fi

  if [ -n "${users_ssh}" ]; then
    install -d -m 700 "/home/${user_login}/.ssh"
    printf '%s\n' "${users_ssh}" >> "/home/${user_login}/.ssh/authorized_keys"
    chmod 600 "/home/${user_login}/.ssh/authorized_keys"
  fi

  chown -R "${user_login}:" "/home/${user_login}"
done

echo "Done."
