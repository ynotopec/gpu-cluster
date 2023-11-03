# K8S GPU ML AI Installation Documentation

This document guides you through the process of setting up a Kubernetes (K8s) environment locally on a Linux machine for GPU-enabled machine learning and artificial intelligence workloads using MicroK8s. Please ensure your system meets the hardware requirements, including a compatible GPU for ML/AI tasks.

## Prerequisites

1. A Linux-based operating system.
2. Snap package manager installed.
3. A compatible GPU with the necessary drivers installed.

## Installation Steps

### Install MicroK8s

MicroK8s is a lightweight Kubernetes distribution that can run on a local machine. To install MicroK8s, use the following command:

```bash
snap install microk8s --classic
```

### Start and Watch MicroK8s Status

*(These commands are commented out in the provided script. Uncomment if needed.)*

```bash
# microk8s.start
# watch microk8s status
```

### Enable MicroK8s Addons

Enable necessary addons including Helm 3, DNS, hostpath storage, Ingress, and RBAC for Kubernetes:

```bash
microk8s enable helm3 dns community hostpath-storage ingress rbac
```

### Configure MetalLB

MetalLB is a load-balancer implementation for bare metal Kubernetes clusters. To enable MetalLB, set the `dhcpList` environment variable to your IP address range and run the command:

```bash
export dhcpList=<YOUR-DHCP-RANGE>
[ ! -z "${dhcpList}" ] && microk8s enable metallb:${dhcpList}
```

Replace `<YOUR-DHCP-RANGE>` with your actual DHCP IP range.

### Enable GPU Support

To enable GPU support in MicroK8s, execute:

```bash
microk8s enable gpu
```

### Install and Configure kubectl

Kubectl is the command-line tool for Kubernetes. Install it and set up an alias to use with MicroK8s:

```bash
snap install kubectl --classic
snap alias microk8s.kubectl kubectl
```

### Configure Helm Alias

Helm is a package manager for Kubernetes. After installing it with MicroK8s, set up an alias for ease of use:

```bash
snap alias microk8s.helm3 helm
```

### Set Up Kubernetes Configuration

To interact with your Kubernetes cluster, set up the `KUBECONFIG` environment variable:

```bash
export KUBECONFIG=${HOME}/.kube/config
mkdir -p ${HOME}/.kube
microk8s.kubectl config view --raw > $KUBECONFIG
```

### Create Namespace and Set Context

Finally, create a new namespace named `infra-root` and set it as the default context for your kubectl commands:

```bash
kubectl create namespace infra-root
kubectl config set-context --current --namespace=infra-root
```

## Post-installation

After completing these steps, your Kubernetes cluster should be up and running with GPU support. You can now deploy GPU-accelerated ML/AI applications to your cluster.

## Verify Installation

To ensure that everything is set up correctly, run the following command to check the status of your nodes and enabled addons:

```bash
microk8s status --wait-ready
```

Also, verify that your GPU is recognized by the cluster:

```bash
kubectl get nodes "-o=custom-columns=NAME:.metadata.name,GPU:.status.allocatable.nvidia\.com/gpu"
```

## Troubleshooting

If you encounter any issues during installation, check the following:

- Ensure your GPU drivers are correctly installed and compatible with your Kubernetes version.
- Verify that all commands are executed with proper permissions. Use `sudo` if required.
- Consult the MicroK8s documentation for specific troubleshooting related to the addons.

## Additional Resources

For more information on MicroK8s, visit the official documentation: [MicroK8s Documentation](https://microk8s.io/docs/)

For more details on Kubernetes, refer to the official Kubernetes documentation: [Kubernetes Documentation](https://kubernetes.io/docs/home/)

## Conclusion

You now have a local Kubernetes cluster powered by MicroK8s with GPU support, ready for running machine learning and artificial intelligence workloads.
