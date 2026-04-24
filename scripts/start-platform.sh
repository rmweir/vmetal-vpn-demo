#!/bin/bash
set -euo pipefail

# Creates a local platform-host vCluster and starts vCluster Platform on it.
#
# Usage:
#   LICENSE_TOKEN=<token> ./scripts/start-platform.sh
#   ./scripts/start-platform.sh  # will prompt for token

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

PLATFORM_IMAGE="ghcr.io/rmweir/re:test12"
VCLUSTER_NAME="platform-host"
NODE_KEY_FILE="$HOME/.ssh/vmetal-demo/node-key"
CERT_MANAGER_VERSION="v1.19.2"

green()  { echo -e "\033[0;32m$*\033[0m"; }
yellow() { echo -e "\033[0;33m$*\033[0m"; }
red()    { echo -e "\033[0;31m$*\033[0m"; }

# --- Node SSH key ---

echo "==> Checking for node SSH key..."
if [ -f "$NODE_KEY_FILE" ]; then
  green "    Reusing existing node key at $NODE_KEY_FILE."
else
  echo "==> Generating node SSH key..."
  mkdir -p "$(dirname "$NODE_KEY_FILE")"
  chmod 700 "$(dirname "$NODE_KEY_FILE")"
  ssh-keygen -t ed25519 -f "$NODE_KEY_FILE" -N "" -C "vmetal-demo-node"
  green "    Node key created at $NODE_KEY_FILE"
fi

NODE_PUBLIC_KEY=$(cat "${NODE_KEY_FILE}.pub")

# --- License token ---

if [ -z "${LICENSE_TOKEN:-}" ]; then
  read -rsp "License token: " LICENSE_TOKEN
  echo ""
fi
if [ -z "${LICENSE_TOKEN:-}" ]; then
  red "LICENSE_TOKEN is required."
  exit 1
fi

# --- Create platform-host vCluster ---

echo "==> Creating/upgrading '$VCLUSTER_NAME' vCluster..."
vcluster create "$VCLUSTER_NAME" \
  --values "$REPO_ROOT/platform/vcluster-nodes.yaml" \
  --upgrade \
  --debug \
  --driver docker

echo "==> Connecting to '$VCLUSTER_NAME'..."
vcluster connect "$VCLUSTER_NAME" --driver docker --update-current

# --- Install cert-manager ---

echo "==> Installing cert-manager ${CERT_MANAGER_VERSION}..."
helm upgrade --install cert-manager cert-manager \
  --repo https://charts.jetstack.io \
  --namespace cert-manager \
  --create-namespace \
  --version "${CERT_MANAGER_VERSION}" \
  --set crds.enabled=true \
  --wait

# --- Start vCluster Platform ---

echo "==> Starting vCluster Platform..."
vcluster use driver helm
vcluster platform start \
  --upgrade \
  --values <(cat <<EOF
config:
  costControl:
    enabled: false
env:
  LICENSE_TOKEN: ${LICENSE_TOKEN}
image: ${PLATFORM_IMAGE}
imageRef:
  registry: ${PLATFORM_IMAGE%%/*}
  repository: $(echo "${PLATFORM_IMAGE}" | cut -d/ -f2- | cut -d: -f1)
  tag: ${PLATFORM_IMAGE##*:}
EOF
)

green "==> Platform is ready."

# --- Generate and apply platform manifests ---

echo "==> Generating manifests/ssh-key.yaml..."
cat > "$REPO_ROOT/manifests/ssh-key.yaml" <<EOF
apiVersion: storage.loft.sh/v1
kind: SSHKey
metadata:
  name: demo
spec:
  publicKey: ${NODE_PUBLIC_KEY}
EOF

echo "==> Applying platform manifests..."
for i in $(seq 1 10); do
  kubectl apply \
    -f "$REPO_ROOT/manifests/node-environment.yaml" \
    -f "$REPO_ROOT/manifests/os-image.yaml" \
    -f "$REPO_ROOT/manifests/ssh-key.yaml" && break
  yellow "    Platform API not ready yet, retrying in 10s... ($i/10)"
  sleep 10
done

green "==> Done."
echo "    Node key: $NODE_KEY_FILE"
