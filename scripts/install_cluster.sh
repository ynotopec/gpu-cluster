#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"
# shellcheck source=scripts/lib/env.sh
source "${SCRIPT_DIR}/lib/env.sh"

load_repo_env

MAIL_EXPIRE="${MAIL_EXPIRE:-admin@example.com}"
ENABLE_LETSENCRYPT="${ENABLE_LETSENCRYPT:-1}"
LETSENCRYPT_INGRESS_CLASS="${LETSENCRYPT_INGRESS_CLASS:-auto}"
METALLB_RANGE="${1:-}"
GPU_TIME_SLICING_REPLICAS="${GPU_TIME_SLICING_REPLICAS:-25}"
GPU_TIME_SLICING_DEFAULT_PROFILE="${GPU_TIME_SLICING_DEFAULT_PROFILE:-any}"

is_truthy() {
  local value="${1:-}"
  case "${value,,}" in
    1|true|yes|on) return 0 ;;
    *) return 1 ;;
  esac
}

install_microk8s() {
  if ! command -v microk8s >/dev/null 2>&1; then
    log "Installing MicroK8s via snap..."
    install_if_missing snap snap
    snap install microk8s --classic --channel=latest/stable
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
  local addons=(hostpath-storage rbac host-access ingress metrics-server gpu cert-manager)
  local failed_addons=()
  local addon

  # `community` must be enabled first because some addons are only available once it is active.
  log "Enabling addon: community"
  if ! microk8s enable community; then
    log "WARNING: Failed to enable addon: community"
    failed_addons+=("community")
  fi

  for addon in "${addons[@]}"; do
    log "Enabling addon: ${addon}"
    if ! microk8s enable "${addon}"; then
      log "WARNING: Failed to enable addon: ${addon}"
      failed_addons+=("${addon}")
    fi
  done

  if [[ -n "${METALLB_RANGE}" ]]; then
    log "Enabling MetalLB range: ${METALLB_RANGE}"
    if ! microk8s enable "metallb:${METALLB_RANGE}"; then
      log "WARNING: Failed to enable addon: metallb:${METALLB_RANGE}"
      failed_addons+=("metallb:${METALLB_RANGE}")
    fi
  fi

  if (( ${#failed_addons[@]} > 0 )); then
    log "Addon installation incomplete. Missing/failed addons: ${failed_addons[*]}"
  else
    log "All requested addons enabled successfully."
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
  if ! is_truthy "${ENABLE_LETSENCRYPT}"; then
    log "Skipping letsencrypt ClusterIssuer creation (ENABLE_LETSENCRYPT=${ENABLE_LETSENCRYPT})."
    return 0
  fi

  log "Provisioning ClusterIssuer letsencrypt-prod"

  log "Waiting for cert-manager CRDs to become available..."
  local crd_wait_attempts=60
  local crd_wait_sleep=5
  local crd_wait_try
  for ((crd_wait_try = 1; crd_wait_try <= crd_wait_attempts; crd_wait_try++)); do
    if microk8s.kubectl get crd clusterissuers.cert-manager.io >/dev/null 2>&1; then
      break
    fi
    if (( crd_wait_try == crd_wait_attempts )); then
      die "Timed out waiting for cert-manager CRD clusterissuers.cert-manager.io."
    fi
    sleep "${crd_wait_sleep}"
  done

  log "Waiting for cert-manager controllers to become ready..."
  microk8s.kubectl rollout status deployment/cert-manager -n cert-manager --timeout=300s
  microk8s.kubectl rollout status deployment/cert-manager-webhook -n cert-manager --timeout=300s
  microk8s.kubectl rollout status deployment/cert-manager-cainjector -n cert-manager --timeout=300s

  local selected_ingress_class="${LETSENCRYPT_INGRESS_CLASS}"
  local solver_ingress_block=""
  if [[ "${selected_ingress_class}" == "auto" ]]; then
    if microk8s.kubectl get ingressclass public >/dev/null 2>&1; then
      selected_ingress_class="public"
    elif microk8s.kubectl get ingressclass nginx >/dev/null 2>&1; then
      selected_ingress_class="nginx"
    elif microk8s.kubectl get ingressclass traefik >/dev/null 2>&1; then
      selected_ingress_class="traefik"
    else
      selected_ingress_class=""
      log "No IngressClass named public, nginx, or traefik found; using cert-manager default ingress solver behavior."
    fi
  fi

  if [[ -z "${selected_ingress_class}" ]]; then
    solver_ingress_block="{}"
    log "Using cert-manager default ingress solver behavior (no explicit ingress class)."
  elif [[ "${selected_ingress_class}" == "public" ]]; then
    # The MicroK8s ingress addon commonly uses legacy ingress class annotation (`class: public`).
    solver_ingress_block=$'class: public'
    log "Using legacy ingress class annotation 'public' for letsencrypt ClusterIssuer solver."
  else
    solver_ingress_block=$"ingressClassName: ${selected_ingress_class}"
    log "Using IngressClass '${selected_ingress_class}' for letsencrypt ClusterIssuer solver."
  fi

  local issuer_apply_attempts=12
  local issuer_apply_sleep=5
  local issuer_apply_try
  local issuer_applied="0"
  for ((issuer_apply_try = 1; issuer_apply_try <= issuer_apply_attempts; issuer_apply_try++)); do
    if cat <<EOF_ISSUER | microk8s.kubectl apply -f -
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
            ${solver_ingress_block}
EOF_ISSUER
    then
      issuer_applied="1"
      break
    fi

    if (( issuer_apply_try == issuer_apply_attempts )); then
      die "Failed to apply ClusterIssuer letsencrypt-prod after ${issuer_apply_attempts} attempts."
    fi

    log "ClusterIssuer apply failed (attempt ${issuer_apply_try}/${issuer_apply_attempts}); retrying in ${issuer_apply_sleep}s..."
    sleep "${issuer_apply_sleep}"
  done

  [[ "${issuer_applied}" == "1" ]] || die "ClusterIssuer apply did not complete successfully."
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
