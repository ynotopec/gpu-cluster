SHELL := /usr/bin/env bash
.SHELLFLAGS := -eu -o pipefail -c

ROOT_SCRIPTS := install.sh upgrade.sh add-users.sh fix-admin.sh
SCRIPT_SOURCES := $(shell find scripts -type f -name '*.sh' | sort)
SCRIPTS := $(ROOT_SCRIPTS) $(SCRIPT_SOURCES)

.PHONY: help lint format check install upgrade add-users fix-admin

help: ## Show available commands
	@awk 'BEGIN {FS = ":.*##"; printf "Usage:\n  make <target>\n\nTargets:\n"} /^[a-zA-Z_-]+:.*##/ { printf "  %-12s %s\n", $$1, $$2 }' $(MAKEFILE_LIST)

lint: ## Run static checks for shell scripts
	@shellcheck $(SCRIPTS)

format: ## Format shell scripts in place
	@shfmt -w -i 2 -ci $(SCRIPTS)

check: lint ## Alias for CI checks

install: ## Run cluster install (reads .env automatically)
	@sudo ./install.sh "$(METALLB_RANGE)"

upgrade: ## Upgrade packages and reconcile cluster
	@sudo ./upgrade.sh

add-users: ## Create users (set USERS and optional USER_SSH_KEY)
	@test -n "$(USERS)" || (echo "USERS is required" >&2; exit 1)
	@sudo USER_PASSWORD="$(USER_PASSWORD)" ./add-users.sh "$(USERS)" "$(USER_SSH_KEY)"

fix-admin: ## Grant admin/kube access (set USERS and KUBECONFIG)
	@test -n "$(USERS)" || (echo "USERS is required" >&2; exit 1)
	@test -n "$(KUBECONFIG)" || (echo "KUBECONFIG is required" >&2; exit 1)
	@sudo KUBECONFIG="$(KUBECONFIG)" ./fix-admin.sh "$(USERS)"
