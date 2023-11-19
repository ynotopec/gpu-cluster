#!/bin/bash

# Automated Installation Script for K8S GPU ML AI using MicroK8s

# Function to enable MicroK8s addons
enable_addons() {
  microk8s enable helm3 dns community hostpath-storage ingress rbac cert-manager
  
  # Check if a DHCP IP range is provided as the first argument ($1)
  if [ -n "$1" ]; then
    echo "Enabling MetalLB with IP range $1..."
    microk8s enable metallb:$1
  fi

  echo "Enabling GPU support..."
  microk8s enable gpu
}

# Function to configure kubectl and set namespace
configure_kubectl() {
  echo "Installing and configuring kubectl..."
  snap install kubectl --classic
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

# Enable addons with the DHCP IP range passed as the first argument
enable_addons "$1"

# Configure kubectl
configure_kubectl

# Install Helm and set alias
echo "Installing and setting alias for Helm..."
snap alias microk8s.helm3 helm

# Installation complete
echo "Installation of K8S GPU ML AI with MicroK8s is complete."

# Final status check
microk8s status --wait-ready
