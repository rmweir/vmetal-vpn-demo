#!/bin/bash
set -euo pipefail

# Provisions a t3.large EC2 instance, creates a vind cluster on it, and
# registers it with vCluster Platform as "metal-cp" — the host cluster for
# the vCluster control plane.
#
# Idempotent: safe to re-run.
#
# Run after `make platform-start`.
#
# Usage:
#   ./scripts/start-cp-cluster.sh

REGION="${REGION:-us-west-2}"
CLUSTER_NAME="metal-cp"
TUNNEL_PORT=19444  # separate port from rack-connect (19443)

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

green()  { echo -e "\033[0;32m$*\033[0m"; }
yellow() { echo -e "\033[0;33m$*\033[0m"; }
red()    { echo -e "\033[0;31m$*\033[0m"; }

ssh_cmd() {
  ssh -i "$SSH_KEY_FILE" -o StrictHostKeyChecking=no ubuntu@"$PUBLIC_IP" "$@"
}

# --- SSH key ---
KEY_VARS=$("$SCRIPT_DIR/create-ssh-key.sh" --region "$REGION") || exit 1
eval "$KEY_VARS"

# --- Provision EC2 instance ---
echo "==> Provisioning CP node EC2 instance..."
tofu -chdir="$REPO_ROOT/cp-node" init -input=false -upgrade 2>/dev/null
tofu -chdir="$REPO_ROOT/cp-node" apply -auto-approve \
  -var ssh_key_name="$SSH_KEY_NAME" \
  -var region="$REGION"

PUBLIC_IP=$(tofu -chdir="$REPO_ROOT/cp-node" output -raw public_ip)
echo "==> CP node ready at $PUBLIC_IP"

# --- Wait for SSH ---
echo "==> Waiting for SSH..."
until ssh -i "$SSH_KEY_FILE" -o StrictHostKeyChecking=no -o ConnectTimeout=5 \
  -o BatchMode=yes ubuntu@"$PUBLIC_IP" true 2>/dev/null; do
  printf "."
  sleep 5
done
echo ""

# --- Bootstrap tools ---
echo "==> Bootstrapping CP node..."
ssh_cmd 'bash -s' < "$SCRIPT_DIR/bootstrap-rack.sh"

# --- Create vind cluster on remote ---
echo "==> Creating vind cluster '$CLUSTER_NAME' on CP node..."
ssh_cmd "vcluster create $CLUSTER_NAME --driver docker --upgrade"
ssh_cmd "vcluster connect $CLUSTER_NAME --driver docker --print > ~/cp-kubeconfig"
green "    vind cluster '$CLUSTER_NAME' is running."

# --- Tunnel to vind cluster API server ---
echo "==> Getting CP vind cluster API server port..."
CP_RAW=$(ssh_cmd "cat ~/cp-kubeconfig")
REMOTE_PORT=$(echo "$CP_RAW" | grep -oP 'server: https://[^:]+:\K\d+' | head -1)
echo "    CP vind API server on EC2: port $REMOTE_PORT"

echo "==> Tunneling CP vind cluster API server (localhost:${TUNNEL_PORT} -> EC2:${REMOTE_PORT})..."
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

echo "$CP_RAW" \
  | sed "s|server: https://[^:]*:${REMOTE_PORT}|server: https://127.0.0.1:${TUNNEL_PORT}|g" \
  > "$KUBECONFIG_FILE"
CONTEXT_NAME=$(grep 'current-context:' "$KUBECONFIG_FILE" | awk '{print $2}')
echo "    Context: $CONTEXT_NAME"

# --- Register with platform (idempotent) ---
if kubectl get clusters.storage.loft.sh "$CLUSTER_NAME" &>/dev/null; then
  yellow "==> Cluster '$CLUSTER_NAME' already connected to platform, skipping."
else
  echo "==> Connecting '$CLUSTER_NAME' to vCluster Platform..."
  KUBECONFIG="$HOME/.kube/config:$KUBECONFIG_FILE" \
    vcluster platform add cluster "$CLUSTER_NAME" \
      --display-name "$CLUSTER_NAME" \
      --context "$CONTEXT_NAME"
fi

green "==> $CLUSTER_NAME is connected to the platform."
echo ""
echo "    Instance: $PUBLIC_IP  (t3.large)"
echo "    Next:     make node-vcluster && make node-claim"
