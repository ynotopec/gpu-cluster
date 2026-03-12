#!/bin/bash
set -euo pipefail

# Admin list example:
# last | cut -d' ' -f1 | grep -vwP 'root|reboot|wtmp' | grep . | sort | uniq -c | sort -nr | awk '{print $2}'

usersList="${1:-${usersList:-}}"

if [ -z "${usersList}" ]; then
  echo "No users provided. Pass a newline-separated list as the first argument or set usersList."
  exit 0
fi

if [ -z "${KUBECONFIG:-}" ] || [ ! -f "${KUBECONFIG}" ]; then
  echo "KUBECONFIG must point to an existing file."
  exit 1
fi

backup_config="${HOME}/.kubeconfig.bck"
cp "${KUBECONFIG}" "${backup_config}"
trap 'cp "${backup_config}" "${KUBECONFIG}"' EXIT

echo "${usersList}" | while IFS= read -r userLogin; do
  [ -z "${userLogin}" ] && continue

  if [ -f /etc/debian_version ]; then
    # Debian-based distribution
    usermod -aG sudo "${userLogin}"
  elif [ -f /etc/redhat-release ]; then
    # RedHat-based distribution
    usermod -aG wheel "${userLogin}"
  fi

  userHome="$(getent passwd "${userLogin}" | cut -d: -f6)"
  [ -z "${userHome}" ] && continue

  kubectl config set-context --current --namespace="home-${userLogin}"
  install -d -m 700 "${userHome}/.kube"
  kubectl config view --raw > "${userHome}/.kube/config"
  chown -R "${userLogin}:" "${userHome}/.kube"

  # Add privileged SCC for OpenShift (ignored on non-OpenShift clusters)
  oc adm policy add-scc-to-user privileged -z default -n "home-${userLogin}" 2>/dev/null || true
done
