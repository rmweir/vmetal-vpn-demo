.PHONY: vind-up vind-down install-multus install-kubevirt install-bridge install-cni-static create-rack

CLUSTER_NAME ?= vmetal-rack
KUBECONFIG := $(CURDIR)/kubeconfig
export KUBECONFIG

KUBEVIRT_VERSION ?= v1.7.1
CDI_VERSION      ?= v1.64.0

vind-up:
	vcluster --driver docker create $(CLUSTER_NAME) --upgrade
	vcluster --driver docker connect $(CLUSTER_NAME) --print > $(KUBECONFIG)

vind-down:
	vcluster --driver docker delete $(CLUSTER_NAME)
	rm -f $(KUBECONFIG)

install-multus:
	kubectl apply -f https://raw.githubusercontent.com/k8snetworkplumbingwg/multus-cni/master/deployments/multus-daemonset-thick.yml
	kubectl rollout status daemonset/kube-multus-ds -n kube-system --timeout=120s

install-kubevirt:
	kubectl apply -f https://github.com/kubevirt/kubevirt/releases/download/$(KUBEVIRT_VERSION)/kubevirt-operator.yaml
	kubectl apply -f https://github.com/kubevirt/kubevirt/releases/download/$(KUBEVIRT_VERSION)/kubevirt-cr.yaml
	kubectl wait --for=condition=Available --timeout=300s -n kubevirt deployment/virt-operator
	kubectl wait --for=condition=Available --timeout=300s -n kubevirt deployment/virt-api
	kubectl apply -f https://github.com/kubevirt/containerized-data-importer/releases/download/$(CDI_VERSION)/cdi-operator.yaml
	kubectl apply -f https://github.com/kubevirt/containerized-data-importer/releases/download/$(CDI_VERSION)/cdi-cr.yaml
	kubectl wait --for=condition=Available --timeout=300s -n cdi deployment/cdi-operator

install-bridge:
	kubectl apply -f manifests/bridge-setup.yaml

install-cni-static:
	kubectl apply -f manifests/cni-static-plugin.yaml
	kubectl rollout status daemonset/cni-static-plugin -n kube-system --timeout=120s

# Deploy VMs + VirtualBMC only (BareMetalHost resources are applied separately against the platform cluster)
create-rack:
	helm upgrade --install vm vm/ --namespace default --set bmh.enabled=false
