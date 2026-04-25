.PHONY: setup platform-start cp-start cp-down cp-ip cp-ssh rack-init rack-up rack-down rack-ip rack-ssh rack-provision rack-connect node-vcluster

SSH_KEY_NAME ?=
SSH_KEY_FILE ?= $(HOME)/.ssh/$(SSH_KEY_NAME).pem
REGION       ?= us-west-2

require-ssh-key:
	@[ -n "$(SSH_KEY_NAME)" ] || (echo "SSH_KEY_NAME is required — e.g. make rack-up SSH_KEY_NAME=my-key" && exit 1)

setup:
	./scripts/setup.sh

platform-start:
	./scripts/start-platform.sh

cp-start:
	./scripts/start-cp-cluster.sh

cp-down:
	tofu -chdir=cp-node destroy -var ssh_key_name=$$(tofu -chdir=cp-node output -raw ssh_key_name 2>/dev/null || echo "unused") -var region=$(REGION)

cp-ip:
	@tofu -chdir=cp-node output -raw public_ip

cp-ssh: require-ssh-key
	@ssh -i $(SSH_KEY_FILE) ubuntu@$$(tofu -chdir=cp-node output -raw public_ip)

rack-init:
	tofu -chdir=rack init

rack-up: rack-init require-ssh-key
	tofu -chdir=rack apply -var ssh_key_name=$(SSH_KEY_NAME) -var region=$(REGION)

rack-down:
	tofu -chdir=rack destroy -var ssh_key_name=$$(tofu -chdir=rack output -raw ssh_key_name 2>/dev/null || echo "unused") -var region=$(REGION)

rack-ip:
	@tofu -chdir=rack output -raw public_ip

rack-ssh: require-ssh-key
	@ssh -i $(SSH_KEY_FILE) ubuntu@$$(tofu -chdir=rack output -raw public_ip)

rack-provision:
	REGION=$(REGION) ./scripts/provision-rack.sh

rack-connect:
	REGION=$(REGION) ./scripts/connect-rack.sh

node-vcluster:
	kubectl apply -f manifests/metal-vcluster.yaml
