#!/bin/bash
set -euo pipefail

# Connects the vind cluster (which hosts KubeVirt VMs and Metal3) to vCluster
# Platform by installing the platform agent. Registers it as "rack-mgmt" so the
# NodeProvider can deploy Metal3/dhcp-proxy onto it with L2 access to br0.
# Uses SSH tunneling so the vind API server doesn't need to be publicly reachable.
#
# Idempotent: safe to re-run.
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

# --- Get vind cluster kubeconfig from EC2 ---
echo "==> Getting vind cluster kubeconfig from EC2..."
RACK_MGMT_RAW=$(ssh_cmd "cat ~/kubevirt/kubeconfig")
REMOTE_PORT=$(echo "$RACK_MGMT_RAW" | grep -oP 'server: https://[^:]+:\K\d+' | head -1)
echo "    vind cluster API server on EC2: port $REMOTE_PORT"

# --- Open SSH tunnel (kill stale process on port first) ---
echo "==> Tunneling vind cluster API server (localhost:${TUNNEL_PORT} -> EC2:${REMOTE_PORT})..."
EXISTING_PID=$(lsof -t -i:"${TUNNEL_PORT}" 2>/dev/null | head -1 || true)
if [ -n "${EXISTING_PID:-}" ]; then
  yellow "    Killing stale tunnel PID $EXISTING_PID on port ${TUNNEL_PORT}..."
  kill "$EXISTING_PID" 2>/dev/null || true
  sleep 1
fi
ssh -f -N \
  -i "$SSH_KEY_FILE" \
  -o StrictHostKeyChecking=no \
  -o ExitOnForwardFailure=yes \
  -L "${TUNNEL_PORT}:127.0.0.1:${REMOTE_PORT}" \
  ubuntu@"$PUBLIC_IP"
FORWARD_TUNNEL_PID=$(lsof -t -i:"${TUNNEL_PORT}" 2>/dev/null | head -1 || true)
KUBECONFIG_FILE=$(mktemp --suffix=.yaml)
cleanup() {
  [ -n "${FORWARD_TUNNEL_PID:-}" ] && kill "$FORWARD_TUNNEL_PID" 2>/dev/null || true
  rm -f "$KUBECONFIG_FILE"
}
trap cleanup EXIT

# Build patched kubeconfig pointing at the local tunnel
echo "$RACK_MGMT_RAW" \
  | sed "s|server: https://[^:]*:${REMOTE_PORT}|server: https://127.0.0.1:${TUNNEL_PORT}|g" \
  > "$KUBECONFIG_FILE"
CONTEXT_NAME=$(grep 'current-context:' "$KUBECONFIG_FILE" | awk '{print $2}')
echo "    Context: $CONTEXT_NAME"

# --- Connect rack-mgmt to platform (idempotent) ---
if kubectl get clusters.storage.loft.sh "$CLUSTER_NAME" &>/dev/null; then
  yellow "==> Cluster '$CLUSTER_NAME' already connected to platform, skipping."
else
  echo "==> Connecting rack-mgmt to platform..."
  KUBECONFIG="$HOME/.kube/config:$KUBECONFIG_FILE" \
    vcluster platform add cluster "$CLUSTER_NAME" \
      --display-name "$CLUSTER_NAME" \
      --context "$CONTEXT_NAME"
  green "==> rack-mgmt is connected to the platform."
fi

# --- Apply NodeProvider ---
echo "==> Applying node-provider.yaml..."
kubectl apply -f "$REPO_ROOT/manifests/node-provider.yaml"

# --- Wait for Metal3 BareMetalHost CRD on rack-mgmt ---
echo "==> Waiting for Metal3 to be deployed on rack-mgmt (may take a few minutes)..."
for i in $(seq 1 30); do
  if KUBECONFIG="$KUBECONFIG_FILE" kubectl get crd baremetalhosts.metal3.io &>/dev/null; then
    green "    Metal3 CRDs are ready."
    break
  fi
  if [ "$i" -eq 30 ]; then
    red "Timed out waiting for Metal3 CRDs on rack-mgmt."
    exit 1
  fi
  yellow "    Waiting for Metal3... ($i/30)"
  sleep 10
done

# --- Register BareMetalHost on rack-mgmt ---
echo "==> Registering BareMetalHost on rack-mgmt..."
for i in $(seq 1 10); do
  if KUBECONFIG="$KUBECONFIG_FILE" kubectl apply -f "$REPO_ROOT/manifests/bmh.yaml"; then
    break
  fi
  yellow "    Metal3 webhook not ready yet, retrying in 10s... ($i/10)"
  sleep 10
done

green "==> Done."
echo ""
echo "    BareMetalHost 'bare-metal-1' is registered and will begin inspecting."
echo "    Next: make cp-start && make node-vcluster && make node-claim"
