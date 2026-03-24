# GPU Cluster Bootstrap (MicroK8s)

Lean automation for provisioning a GPU-capable MicroK8s host and onboarding users.

## Project structure

- `install.sh` – primary idempotent installer entrypoint (loads `.env` automatically).
- `upgrade.sh` – host/package refresh + idempotent cluster reconciliation.
- `scripts/install_cluster.sh` – installs/configures MicroK8s + addons.
- `scripts/add_users.sh` – creates users, applies SSH keys, forces first-login password reset.
- `scripts/fix_admin.sh` – grants admin-group access and writes per-user kubeconfig.
- `scripts/lib/common.sh` – shared shell utilities (logging, validation, package install helper).
- `scripts/lib/env.sh` – shared `.env` loader for root-level entrypoints.
- `Makefile` – repeatable linting/formatting/check workflows + common operational commands.

## Quick start

```bash
cp .env.example .env
sudo ./install.sh
```

You can still pass MetalLB range inline:

```bash
sudo ./install.sh "192.168.1.200-192.168.1.220"
```

Optional environment variables (from `.env` or process env):

- `MAIL_EXPIRE` (default: `admin@example.com`) for cert-manager issuer email.
- `ENABLE_LETSENCRYPT=1` to create a `letsencrypt-prod` ClusterIssuer.
- `METALLB_RANGE` to configure MetalLB.
- `GPU_TIME_SLICING_REPLICAS` (default: `25`) to set GPU operator time-slicing replicas for the `any` profile and bundled MIG profiles.
- `GPU_TIME_SLICING_DEFAULT_PROFILE` (default: `any`) to choose the default profile key in `time-slicing-config-fine` (recommended for mixed fleets, including DGX Spark).

Create users (newline-separated):

```bash
sudo USER_PASSWORD='ChangeMeNow!' ./add-users.sh $'alice\nbob' 'ssh-ed25519 AAAA...'
```

Grant Kubernetes/admin access:

```bash
sudo KUBECONFIG=/home/admin/.kube/config ./fix-admin.sh $'alice\nbob'
```

Reconcile packages + cluster (idempotent):

```bash
sudo ./upgrade.sh
```

## Repeatable maintenance

```bash
make lint          # shellcheck
make format        # shfmt
make check         # CI-friendly checks
```

## Makefile automation

```bash
make install METALLB_RANGE="192.168.1.200-192.168.1.220"
make upgrade
make add-users USERS=$'alice\nbob' USER_PASSWORD='ChangeMeNow!' USER_SSH_KEY='ssh-ed25519 AAAA...'
make fix-admin USERS=$'alice\nbob' KUBECONFIG=/home/admin/.kube/config
```
