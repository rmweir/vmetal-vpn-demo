.PHONY: setup rack-init rack-up rack-down rack-ip rack-ssh rack-provision

SSH_KEY_NAME ?=
SSH_KEY_FILE ?= $(HOME)/.ssh/$(SSH_KEY_NAME).pem
REGION       ?= us-west-2

require-ssh-key:
	@[ -n "$(SSH_KEY_NAME)" ] || (echo "SSH_KEY_NAME is required — e.g. make rack-up SSH_KEY_NAME=my-key" && exit 1)

setup:
	./scripts/setup.sh

rack-init:
	tofu -chdir=rack init

rack-up: rack-init require-ssh-key
	tofu -chdir=rack apply -var ssh_key_name=$(SSH_KEY_NAME) -var region=$(REGION)

rack-down: require-ssh-key
	tofu -chdir=rack destroy -var ssh_key_name=$(SSH_KEY_NAME) -var region=$(REGION)

rack-ip:
	@tofu -chdir=rack output -raw public_ip

rack-ssh: require-ssh-key
	@ssh -i $(SSH_KEY_FILE) ubuntu@$$(tofu -chdir=rack output -raw public_ip)

rack-provision: require-ssh-key
	SSH_KEY_NAME=$(SSH_KEY_NAME) SSH_KEY_FILE=$(SSH_KEY_FILE) REGION=$(REGION) ./scripts/provision-rack.sh
