#!/bin/bash
set -euo pipefail

# Bootstraps a fresh Ubuntu 24.04 EC2 instance with the tools needed to run
# KubeVirt VMs via vcluster-in-docker (vind).
#
# Designed to be run remotely over SSH:
#   ssh ubuntu@<ip> 'bash -s' < scripts/bootstrap-rack.sh

ARCH="$(uname -m)"
case "$ARCH" in
  x86_64)  BIN_ARCH="amd64" ;;
  aarch64) BIN_ARCH="arm64" ;;
  *)       echo "Unsupported architecture: $ARCH"; exit 1 ;;
esac

echo "==> Increasing inotify limits..."
sudo sysctl -w fs.inotify.max_user_watches=524288
sudo sysctl -w fs.inotify.max_user_instances=512
printf 'fs.inotify.max_user_watches=524288\nfs.inotify.max_user_instances=512\n' | sudo tee /etc/sysctl.d/99-vmetal.conf > /dev/null

echo "==> Loading required kernel modules..."
sudo modprobe overlay
sudo modprobe bridge
sudo modprobe br_netfilter
printf 'overlay\nbridge\nbr_netfilter\n' | sudo tee /etc/modules-load.d/vmetal.conf > /dev/null

echo "==> Updating apt..."
sudo apt-get update -qq
sudo apt-get install -y -qq make

# --- Docker ---
if ! command -v docker &>/dev/null; then
  echo "==> Installing Docker..."
  curl -fsSL https://get.docker.com | sudo sh
  sudo usermod -aG docker ubuntu
  echo "    Docker installed (re-login or use 'newgrp docker' for group to take effect)"
else
  echo "==> Docker already installed"
fi

# --- kubectl ---
if ! command -v kubectl &>/dev/null; then
  echo "==> Installing kubectl..."
  KUBECTL_VERSION=$(curl -fsSL https://dl.k8s.io/release/stable.txt)
  sudo curl -fsSL "https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/${BIN_ARCH}/kubectl" \
    -o /usr/local/bin/kubectl
  sudo chmod +x /usr/local/bin/kubectl
else
  echo "==> kubectl already installed"
fi

# --- Helm ---
if ! command -v helm &>/dev/null; then
  echo "==> Installing Helm..."
  curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
else
  echo "==> Helm already installed"
fi

# --- vcluster CLI ---
if ! command -v vcluster &>/dev/null; then
  echo "==> Installing vcluster CLI..."
  sudo curl -fsSL "https://github.com/loft-sh/vcluster/releases/latest/download/vcluster-linux-${BIN_ARCH}" \
    -o /usr/local/bin/vcluster
  sudo chmod +x /usr/local/bin/vcluster
else
  echo "==> vcluster CLI already installed"
fi

echo ""
echo "==> Bootstrap complete"
echo "    docker:   $(docker --version)"
echo "    kubectl:  $(kubectl version --client -o json | grep gitVersion | head -1)"
echo "    helm:     $(helm version --short)"
echo "    vcluster: $(vcluster version)"
