# GPU Cluster Bootstrap (MicroK8s)

Minimal scripts to bootstrap a local GPU-ready MicroK8s cluster and user access.

## Files

- `install_k8s_gpu_ml_ai.sh`: installs and configures MicroK8s + common addons.
- `add-users.sh`: creates Linux users, installs SSH keys, and forces password change.
- `fix-admin.sh`: grants admin group access and writes per-user kubeconfig contexts.

## Quick start

```bash
sudo ./install_k8s_gpu_ml_ai.sh "192.168.1.200-192.168.1.220"
```

Optional environment variables:

- `MAIL_EXPIRE`: email used for cert-manager issuer (default: `admin@example.com`).
- `ENABLE_LETSENCRYPT=1`: create a `letsencrypt-prod` ClusterIssuer.

Create users (newline-separated):

```bash
sudo USER_PASSWORD='ChangeMeNow!' ./add-users.sh $'alice\nbob' 'ssh-ed25519 AAAA...'
```

Grant Kubernetes/admin access:

```bash
sudo KUBECONFIG=/home/admin/.kube/config ./fix-admin.sh $'alice\nbob'
```
