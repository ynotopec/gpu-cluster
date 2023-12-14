#!/bin/bash

# Variables
export mailExpire=admin@example.com

# Automated Installation Script for K8S GPU ML AI using MicroK8s

# Function to enable MicroK8s addons
enable_addons() {
  microk8s enable helm3 dns community hostpath-storage ingress rbac metrics-server
  
  # Check if a DHCP IP range is provided as the first argument ($1)
  if [ -n "$1" ]; then
    echo "Enabling MetalLB with IP range $1..."
    microk8s enable metallb:$1
  fi

  echo "Enabling GPU support..."
  microk8s enable gpu

  echo "H100 GPU example"
  cat <<EOT >~/time-slicing-config-fine.yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: time-slicing-config-fine
data:
  h100-80gb: |-
    version: v1
    flags:
      migStrategy: mixed
    sharing:
      timeSlicing:
        resources:
        - name: nvidia.com/gpu
          replicas: 5
#        - name: nvidia.com/mig-1g.10gb
#          replicas: 4
#        - name: nvidia.com/mig-1g.10gb+me
#          replicas: 4
#        - name: nvidia.com/mig-1g.20gb
#          replicas: 4
#        - name: nvidia.com/mig-3g.40gb
#          replicas: 6
#        - name: nvidia.com/mig-4g.40gb
#          replicas: 8
#        - name: nvidia.com/mig-7g.80gb
#          replicas: 14
EOT

  kubectl create -n gpu-operator-resources -f ~/time-slicing-config-fine.yaml
  kubectl patch clusterpolicy/cluster-policy \
    -n gpu-operator-resources --type merge \
    -p '{"spec": {"devicePlugin": {"config": {"name": "time-slicing-config-fine"}}}}'

  #kubectl get events -n gpu-operator-resources --sort-by='.lastTimestamp'

  kubectl label node \
    --selector=nvidia.com/gpu.product=NVIDIA-H100-PCIe \
    nvidia.com/device-plugin.config=h100-80gb

  echo "Configure TLS Issuer"
  microk8s enable cert-manager
  cat <<EOF |kubectl apply -f -
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: letsencrypt-prod
spec:
  acme:
    # L'URL de serveur ACME de Let's Encrypt pour la production
    server: https://acme-v02.api.letsencrypt.org/directory
    email: ${mailExpire}
    privateKeySecretRef:
      name: letsencrypt-prod
    solvers:
    - http01:
        ingress:
          class: public
EOF


}

# Function to configure kubectl and set namespace
configure_kubectl() {
  echo "Configuring kubectl..."
#  snap install kubectl --classic
  snap alias microk8s.kubectl kubectl
  
  # Set up Kubernetes configuration directory and file
  local kube_dir="${HOME}/.kube"
  mkdir -p "${kube_dir}"
  local kube_config="${kube_dir}/config"
  export KUBECONFIG="${kube_config}"
  microk8s.kubectl config view --raw > "${kube_config}"

  # Create namespace and set it as the default context
  kubectl create namespace infra-root
  kubectl config set-context --current --namespace=infra-root
}

# Ensure script is run as root
if [ "$(id -u)" != "0" ]; then
   echo "This script must be run as root" 1>&2
   exit 1
fi

# Install MicroK8s
echo "Installing MicroK8s..."
snap install microk8s --classic
# Optional: Wait for MicroK8s to be up and running
microk8s status --wait-ready

# Configure kubectl
configure_kubectl

# Enable addons with the DHCP IP range passed as the first argument
enable_addons "$1"

# Install Helm and set alias
echo "Installing and setting alias for Helm..."
snap alias microk8s.helm3 helm

# Installation complete
echo "Installation of K8S GPU ML AI with MicroK8s is complete."

# Final status check
microk8s status --wait-ready
