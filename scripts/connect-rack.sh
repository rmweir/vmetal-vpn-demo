#!/bin/bash
set -euo pipefail

# Connects the vind cluster (which hosts KubeVirt VMs and Metal3) to vCluster
# Platform by installing the platform agent. Registers it as "rack-mgmt" so the
# NodeProvider can deploy Metal3/dhcp-proxy onto it with L2 access to br0.
# Uses SSH tunneling so the vind API server doesn't need to be publicly reachable.
#
# Run after both `make platform-start` and `make rack-provision`.
#
# Usage:
#   ./scripts/connect-rack.sh

REGION="${REGION:-us-west-2}"
CLUSTER_NAME="rack-mgmt"
TUNNEL_PORT=19443  # local port forwarded to rack-mgmt API server on EC2

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

green()  { echo -e "\033[0;32m$*\033[0m"; }
yellow() { echo -e "\033[0;33m$*\033[0m"; }
red()    { echo -e "\033[0;31m$*\033[0m"; }

ssh_cmd() {
  ssh -i "$SSH_KEY_FILE" -o StrictHostKeyChecking=no ubuntu@"$PUBLIC_IP" "$@"
}

# --- Get rack connection info ---
PUBLIC_IP=$(make -C "$REPO_ROOT" --no-print-directory rack-ip)
KEY_VARS=$("$SCRIPT_DIR/create-ssh-key.sh" --region "$REGION") || exit 1
eval "$KEY_VARS"

# --- Get platform URL ---
PLATFORM_URL=$(jq -r '.. | objects | select(has("host")) | .host' \
  ~/.vcluster/config.json 2>/dev/null | head -1 || true)
if [ -z "${PLATFORM_URL:-}" ]; then
  read -rp "Platform URL (e.g. https://localhost:8443): " PLATFORM_URL < /dev/tty
fi
echo "==> Platform URL: $PLATFORM_URL"

# --- Get vind cluster kubeconfig from EC2 ---
echo "==> Getting vind cluster kubeconfig from EC2..."
RACK_MGMT_RAW=$(ssh_cmd "cat ~/kubevirt/kubeconfig")
REMOTE_PORT=$(echo "$RACK_MGMT_RAW" | grep -oP 'server: https://[^:]+:\K\d+' | head -1)
echo "    vind cluster API server on EC2: port $REMOTE_PORT"

# --- Open SSH forward tunnel for vind cluster API server ---
echo "==> Tunneling vind cluster API server (localhost:${TUNNEL_PORT} -> EC2:${REMOTE_PORT})..."
ssh -f -N \
  -i "$SSH_KEY_FILE" \
  -o StrictHostKeyChecking=no \
  -o ExitOnForwardFailure=yes \
  -L "${TUNNEL_PORT}:127.0.0.1:${REMOTE_PORT}" \
  ubuntu@"$PUBLIC_IP"
FORWARD_TUNNEL_PID=$(lsof -t -i:"${TUNNEL_PORT}" 2>/dev/null | head -1 || true)
cleanup_forward() { [ -n "${FORWARD_TUNNEL_PID:-}" ] && kill "$FORWARD_TUNNEL_PID" 2>/dev/null || true; }
trap cleanup_forward EXIT

# Build patched kubeconfig pointing at the local tunnel
KUBECONFIG_FILE=$(mktemp --suffix=.yaml)
echo "$RACK_MGMT_RAW" \
  | sed "s|server: https://[^:]*:${REMOTE_PORT}|server: https://127.0.0.1:${TUNNEL_PORT}|g" \
  > "$KUBECONFIG_FILE"
CONTEXT_NAME=$(grep 'current-context:' "$KUBECONFIG_FILE" | awk '{print $2}')
echo "    Context: $CONTEXT_NAME"

# --- Connect rack-mgmt to platform ---
echo "==> Connecting rack-mgmt to platform..."
KUBECONFIG="$HOME/.kube/config:$KUBECONFIG_FILE" \
  vcluster platform add cluster "$CLUSTER_NAME" \
    --display-name "$CLUSTER_NAME" \
    --context "$CONTEXT_NAME"

green "==> rack-mgmt is connected to the platform."
