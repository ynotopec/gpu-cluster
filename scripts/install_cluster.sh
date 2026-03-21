#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"

MAIL_EXPIRE="${MAIL_EXPIRE:-admin@example.com}"
ENABLE_LETSENCRYPT="${ENABLE_LETSENCRYPT:-0}"
METALLB_RANGE="${1:-}"

install_microk8s() {
  if ! command -v microk8s >/dev/null 2>&1; then
    log "Installing MicroK8s via snap..."
    install_if_missing snap snap
    snap install microk8s --classic
  else
    log "MicroK8s already installed; skipping snap install."
  fi

  microk8s status --wait-ready
}

configure_kubectl() {
  if ! command -v kubectl >/dev/null 2>&1; then
    log "Installing kubectl via snap..."
    install_if_missing snap snap
    snap install kubectl --classic
  fi

  local kube_dir="${HOME}/.kube"
  local kube_config="${kube_dir}/config"

  mkdir -p "${kube_dir}"
  microk8s.kubectl config view --raw >"${kube_config}"
  chmod 600 "${kube_config}"

  microk8s.kubectl get namespace infra-root >/dev/null 2>&1 || microk8s.kubectl create namespace infra-root
  KUBECONFIG="${kube_config}" microk8s.kubectl config set-context --current --namespace=infra-root >/dev/null
}

enable_addons() {
  local addons=(community helm3 dns hostpath-storage ingress rbac metrics-server nfs host-access observability gpu)

  for addon in "${addons[@]}"; do
    log "Enabling addon: ${addon}"
    microk8s enable "${addon}"
  done

  if [[ -n "${METALLB_RANGE}" ]]; then
    log "Enabling MetalLB range: ${METALLB_RANGE}"
    microk8s enable "metallb:${METALLB_RANGE}"
  fi
}

configure_letsencrypt_issuer() {
  [[ "${ENABLE_LETSENCRYPT}" == "1" ]] || return 0

  log "Enabling cert-manager and provisioning ClusterIssuer letsencrypt-prod"
  microk8s enable cert-manager

  cat <<EOF_ISSUER | microk8s.kubectl apply -f -
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: letsencrypt-prod
spec:
  acme:
    server: https://acme-v02.api.letsencrypt.org/directory
    email: ${MAIL_EXPIRE}
    privateKeySecretRef:
      name: letsencrypt-prod
    solvers:
      - http01:
          ingress:
            class: public
EOF_ISSUER
}

main() {
  require_root
  install_microk8s
  configure_kubectl
  enable_addons
  configure_letsencrypt_issuer

  snap alias microk8s.helm3 helm >/dev/null 2>&1 || true
  microk8s status --wait-ready

  log "Cluster installation complete."
}

main "$@"
