#!/usr/bin/env bash
set -euo pipefail

MAIL_EXPIRE="${MAIL_EXPIRE:-admin@example.com}"
ENABLE_LETSENCRYPT="${ENABLE_LETSENCRYPT:-0}"
METALLB_RANGE="${1:-}"

if [ "$(id -u)" -ne 0 ]; then
  echo "This script must be run as root."
  exit 1
fi

enable_addons() {
  microk8s enable community
  microk8s enable helm3 dns hostpath-storage ingress rbac metrics-server nfs host-access observability gpu

  if [ -n "${METALLB_RANGE}" ]; then
    echo "Enabling MetalLB with range: ${METALLB_RANGE}"
    microk8s enable "metallb:${METALLB_RANGE}"
  fi
}

configure_kubectl() {
  snap install kubectl --classic

  local kube_dir="${HOME}/.kube"
  local kube_config="${kube_dir}/config"
  mkdir -p "${kube_dir}"
  export KUBECONFIG="${kube_config}"

  microk8s.kubectl config view --raw > "${kube_config}"
  microk8s.kubectl get namespace infra-root >/dev/null 2>&1 || microk8s.kubectl create namespace infra-root
  microk8s.kubectl config set-context --current --namespace=infra-root
}

configure_letsencrypt_issuer() {
  [ "${ENABLE_LETSENCRYPT}" = "1" ] || return 0

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

echo "Installing MicroK8s..."
snap install microk8s --classic
microk8s status --wait-ready

configure_kubectl
enable_addons
configure_letsencrypt_issuer

snap alias microk8s.helm3 helm
microk8s status --wait-ready

echo "MicroK8s GPU bootstrap complete."
