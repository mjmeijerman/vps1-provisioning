SHELL=/bin/bash

.DEFAULT_GOAL := help

## provision-prod: Provisions the production web environment
.PHONY: provision-prod
provision-prod:
	ansible-playbook --limit production -i hosts playbook.yml --ask-vault-pass

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
	ansible-galaxy collection install -r requirements.yml

## help:		Print this message
.PHONY: help
help: Makefile
	@sed -n 's/^##//p' $<
