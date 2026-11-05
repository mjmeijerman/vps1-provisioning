SHELL=/bin/bash

.DEFAULT_GOAL := help

# The vault password file, if it exists. Falls back to a prompt so a colleague
# without it can still run the playbook the old way. See README, "Vault".
VAULT_FILE ?= $(HOME)/.ansible/vault-pass-vps1
VAULT_ARGS := $(if $(wildcard $(VAULT_FILE)),--vault-password-file $(VAULT_FILE),--ask-vault-pass)

## provision-prod: Provisions the production web environment
.PHONY: provision-prod
provision-prod:
	ansible-playbook --limit production -i hosts playbook.yml $(VAULT_ARGS) $(ARGS)

## provision-prod-dry: Reports what would change, changes nothing
.PHONY: provision-prod-dry
provision-prod-dry:
	ansible-playbook --limit production -i hosts playbook.yml --check --diff $(VAULT_ARGS) $(ARGS)

## syntax-check: Parses the playbook without touching the host
.PHONY: syntax-check
syntax-check:
	ansible-playbook -i hosts playbook.yml --syntax-check

## lint: Checks our own files (roles-galaxy is excluded, see .ansible-lint)
.PHONY: lint
lint:
	ansible-lint

## update-ansible-roles: Updates the ansible roles and collections
.PHONY: update-ansible-roles
update-ansible-roles:
	ansible-galaxy install -r requirements.yml -f
	# Collections go to the user's home: the system path belongs to the distro
	# package and cannot be written without root.
	ansible-galaxy collection install -r requirements.yml -p ~/.ansible/collections

## help:		Print this message
.PHONY: help
help: Makefile
	@sed -n 's/^##//p' $<
