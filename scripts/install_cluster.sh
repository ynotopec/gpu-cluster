#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"

MAIL_EXPIRE="${MAIL_EXPIRE:-admin@example.com}"
ENABLE_LETSENCRYPT="${ENABLE_LETSENCRYPT:-0}"
METALLB_RANGE="${1:-}"
GPU_TIME_SLICING_REPLICAS="${GPU_TIME_SLICING_REPLICAS:-25}"
GPU_TIME_SLICING_DEFAULT_PROFILE="${GPU_TIME_SLICING_DEFAULT_PROFILE:-any}"

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

install_cli_tools() {
  install_if_missing snap snap

  if ! command -v kubectl >/dev/null 2>&1; then
    log "Installing kubectl via snap..."
    snap install kubectl --classic
  fi

  if ! command -v helm >/dev/null 2>&1; then
    log "Installing helm via snap..."
    snap install helm --classic >/dev/null 2>&1 || true
  fi
}

configure_kubeconfig() {
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

configure_gpu_time_slicing() {
  local namespace="gpu-operator"
  local configmap_name="time-slicing-config-fine"
  local apply_output
  local patch_output=""
  local should_restart_device_plugin="0"

  log "Applying NVIDIA GPU Operator time-slicing config (${configmap_name})"

  apply_output="$(cat <<EOF_TIMESLICING | microk8s.kubectl apply -f -
apiVersion: v1
kind: ConfigMap
metadata:
  name: ${configmap_name}
  namespace: ${namespace}
data:
  any: |-
    version: v1
    flags:
      migStrategy: none
    sharing:
      timeSlicing:
        resources:
          - name: nvidia.com/gpu
            replicas: ${GPU_TIME_SLICING_REPLICAS}
  h100-80gb: |-
    version: v1
    flags:
      migStrategy: mixed
    sharing:
      timeSlicing:
        resources:
          - name: nvidia.com/gpu
            replicas: ${GPU_TIME_SLICING_REPLICAS}
  a100-80gb: |-
    version: v1
    flags:
      migStrategy: mixed
    sharing:
      timeSlicing:
        resources:
          - name: nvidia.com/gpu
            replicas: ${GPU_TIME_SLICING_REPLICAS}
  a100-40gb: |-
    version: v1
    flags:
      migStrategy: mixed
    sharing:
      timeSlicing:
        resources:
          - name: nvidia.com/gpu
            replicas: ${GPU_TIME_SLICING_REPLICAS}
EOF_TIMESLICING
)"
  log "${apply_output}"

  if [[ "${apply_output}" != *"unchanged"* ]]; then
    should_restart_device_plugin="1"
  fi

  if microk8s.kubectl get clusterpolicy cluster-policy >/dev/null 2>&1; then
    log "Patching gpu-operator ClusterPolicy to consume time-slicing profiles."
    patch_output="$(cat <<EOF_CLUSTPOL | microk8s.kubectl patch clusterpolicy cluster-policy --type merge --patch-file /dev/stdin
spec:
  devicePlugin:
    config:
      name: ${configmap_name}
      default: ${GPU_TIME_SLICING_DEFAULT_PROFILE}
EOF_CLUSTPOL
)"
    log "${patch_output}"
    if [[ "${patch_output}" != *"no change"* ]]; then
      should_restart_device_plugin="1"
    fi
  else
    log "ClusterPolicy gpu-operator/cluster-policy not found; skipping patch."
  fi

  if [[ "${should_restart_device_plugin}" == "1" ]]; then
    log "Restarting GPU Operator device plugin pods to pick up config changes."
    microk8s.kubectl rollout restart -n "${namespace}" daemonset/nvidia-device-plugin-daemonset >/dev/null 2>&1 || true
    microk8s.kubectl rollout restart -n "${namespace}" daemonset/gpu-feature-discovery >/dev/null 2>&1 || true
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
  install_cli_tools
  configure_kubeconfig
  enable_addons
  configure_gpu_time_slicing
  configure_letsencrypt_issuer

  microk8s status --wait-ready

  log "Cluster installation complete."
}

main "$@"
