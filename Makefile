SHELL := /usr/bin/env bash
.SHELLFLAGS := -eu -o pipefail -c

SCRIPTS := \
	install_k8s_gpu_ml_ai.sh \
	add-users.sh \
	fix-admin.sh \
	scripts/install_cluster.sh \
	scripts/add_users.sh \
	scripts/fix_admin.sh \
	scripts/lib/common.sh

.PHONY: help lint format check

help: ## Show available commands
	@awk 'BEGIN {FS = ":.*##"; printf "Usage:\n  make <target>\n\nTargets:\n"} /^[a-zA-Z_-]+:.*##/ { printf "  %-10s %s\n", $$1, $$2 }' $(MAKEFILE_LIST)

lint: ## Run static checks for shell scripts
	@shellcheck $(SCRIPTS)

format: ## Format shell scripts in place
	@shfmt -w -i 2 -ci $(SCRIPTS)

check: lint ## Alias for CI checks
