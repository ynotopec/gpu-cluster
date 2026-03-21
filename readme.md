# GPU Cluster Bootstrap (MicroK8s)

Lean automation for provisioning a GPU-capable MicroK8s host and onboarding users.

## Project structure

- `scripts/install_cluster.sh` – installs and configures MicroK8s + addons.
- `scripts/add_users.sh` – creates users, applies SSH keys, forces first-login password reset.
- `scripts/fix_admin.sh` – grants admin-group access and writes per-user kubeconfig.
- `scripts/lib/common.sh` – shared shell utilities (logging, validation, package install helper).
- `Makefile` – repeatable linting/formatting/check workflows.
- Legacy wrapper scripts at repo root keep existing command names working.

## Quick start

```bash
sudo ./install_k8s_gpu_ml_ai.sh "192.168.1.200-192.168.1.220"
```

Optional environment variables:

- `MAIL_EXPIRE` (default: `admin@example.com`) for cert-manager issuer email.
- `ENABLE_LETSENCRYPT=1` to create a `letsencrypt-prod` ClusterIssuer.

Create users (newline-separated):

```bash
sudo USER_PASSWORD='ChangeMeNow!' ./add-users.sh $'alice\nbob' 'ssh-ed25519 AAAA...'
```

Grant Kubernetes/admin access:

```bash
sudo KUBECONFIG=/home/admin/.kube/config ./fix-admin.sh $'alice\nbob'
```

## Repeatable maintenance

```bash
make lint     # shellcheck
make format   # shfmt
make check    # CI-friendly checks
```
