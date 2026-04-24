#!/bin/bash
set -euo pipefail

# Provisions the rack EC2 instance and bootstraps it with required tools,
# a vind cluster, KubeVirt, bridge networking, and CNI static plugin.
#
# Usage:
#   ./scripts/provision-rack.sh
#
# Optional:
#   REGION  AWS region (default: us-west-2)

REGION="${REGION:-us-west-2}"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

ssh_cmd() {
  ssh -i "$SSH_KEY_FILE" -o StrictHostKeyChecking=no ubuntu@"$PUBLIC_IP" "$@"
}

# --- Create SSH key pair ---
KEY_VARS=$("$SCRIPT_DIR/create-ssh-key.sh" --region "$REGION") || exit 1
eval "$KEY_VARS"

# --- Create EC2 instance ---
echo "==> Creating rack EC2 instance..."
make -C "$REPO_ROOT" rack-up SSH_KEY_NAME="$SSH_KEY_NAME" REGION="$REGION"

PUBLIC_IP=$(make -C "$REPO_ROOT" --no-print-directory rack-ip)
echo "==> Instance ready at $PUBLIC_IP"

# --- Wait for SSH ---
echo "==> Waiting for SSH to become available..."
until ssh \
  -i "$SSH_KEY_FILE" \
  -o StrictHostKeyChecking=no \
  -o ConnectTimeout=5 \
  -o BatchMode=yes \
  ubuntu@"$PUBLIC_IP" true 2>/dev/null
do
  printf "."
  sleep 5
done
echo ""
echo "==> SSH is ready"

# --- Bootstrap tools ---
echo "==> Installing tools..."
ssh_cmd 'bash -s' < "$SCRIPT_DIR/bootstrap-rack.sh"

# --- Copy kubevirt setup ---
echo "==> Copying kubevirt setup..."
ssh_cmd "cp ~/kubevirt/kubeconfig /tmp/vmetal-kubeconfig 2>/dev/null || true"
ssh_cmd "rm -rf ~/kubevirt"
scp -i "$SSH_KEY_FILE" -o StrictHostKeyChecking=no -r \
  "$REPO_ROOT/kubevirt" \
  ubuntu@"$PUBLIC_IP":~/
ssh_cmd "mv /tmp/vmetal-kubeconfig ~/kubevirt/kubeconfig 2>/dev/null || true"

# --- Create vind cluster ---
echo "==> Creating vind cluster..."
ssh_cmd "make -C ~/kubevirt vind-up"

# --- Install KubeVirt, bridge, CNI ---
echo "==> Installing KubeVirt..."
ssh_cmd "make -C ~/kubevirt install-kubevirt"

echo "==> Setting up bridge network..."
ssh_cmd "make -C ~/kubevirt install-bridge"

echo "==> Installing CNI static plugin..."
ssh_cmd "make -C ~/kubevirt install-cni-static"

echo "==> Installing Multus..."
ssh_cmd "make -C ~/kubevirt install-multus"

# --- Create VMs ---
echo "==> Creating KubeVirt VMs..."
ssh_cmd "make -C ~/kubevirt create-rack"

# --- Forward NodePorts to vind cluster ---
echo "==> Setting up NodePort forwarding to vind cluster..."
VIND_IP=$(ssh_cmd "docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' \$(docker ps -q)" | tail -1)
CONTAINER_ID=$(ssh_cmd "docker ps -q")
echo "    vind cluster IP: $VIND_IP"
ssh_cmd "sudo sysctl -w net.ipv4.ip_forward=1"

# EC2 host → vind container: forward ports 30443 (VirtualBMC) and 30022 (bare metal SSH)
for PORT in 30443 30022; do
  ssh_cmd "sudo iptables -t nat -D PREROUTING -p tcp --dport ${PORT} -j DNAT --to-destination ${VIND_IP}:${PORT} 2>/dev/null || true"
  ssh_cmd "sudo iptables -D FORWARD -p tcp -d ${VIND_IP} --dport ${PORT} -j ACCEPT 2>/dev/null || true"
  ssh_cmd "sudo iptables -t nat -A PREROUTING -p tcp --dport ${PORT} -j DNAT --to-destination ${VIND_IP}:${PORT}"
  ssh_cmd "sudo iptables -I FORWARD 1 -p tcp -d ${VIND_IP} --dport ${PORT} -j ACCEPT"
done
ssh_cmd "sudo iptables -t nat -D POSTROUTING -d ${VIND_IP} -j MASQUERADE 2>/dev/null || true"
ssh_cmd "sudo iptables -D FORWARD -p tcp -s ${VIND_IP} -j ACCEPT 2>/dev/null || true"
ssh_cmd "sudo iptables -t nat -A POSTROUTING -d ${VIND_IP} -j MASQUERADE"
ssh_cmd "sudo iptables -I FORWARD 1 -p tcp -s ${VIND_IP} -j ACCEPT"

# Inside vind container: forward port 30022 → bare metal node SSH (192.168.100.100:22)
# br0 lives in the container's netns so this is the only way to reach it from outside
NODE_IP="192.168.100.100"
ssh_cmd "docker exec ${CONTAINER_ID} iptables -t nat -D PREROUTING -p tcp --dport 30022 -j DNAT --to-destination ${NODE_IP}:22 2>/dev/null || true"
ssh_cmd "docker exec ${CONTAINER_ID} iptables -D FORWARD -p tcp -d ${NODE_IP} --dport 22 -j ACCEPT 2>/dev/null || true"
ssh_cmd "docker exec ${CONTAINER_ID} iptables -t nat -A PREROUTING -p tcp --dport 30022 -j DNAT --to-destination ${NODE_IP}:22"
ssh_cmd "docker exec ${CONTAINER_ID} iptables -I FORWARD 1 -p tcp -d ${NODE_IP} --dport 22 -j ACCEPT"

# --- Install cert-manager on vind cluster (required for Metal3 webhooks) ---
echo "==> Installing cert-manager on vind cluster..."
ssh_cmd "KUBECONFIG=~/kubevirt/kubeconfig \
  helm upgrade --install cert-manager cert-manager \
    --repo https://charts.jetstack.io \
    --namespace cert-manager \
    --create-namespace \
    --version v1.19.2 \
    --set crds.enabled=true \
    --wait"

echo ""
echo "==> Rack is ready"
echo "    SSH:  ssh -i $SSH_KEY_FILE ubuntu@$PUBLIC_IP"
echo "    BMC:  redfish+http://${PUBLIC_IP}:30443"
echo "    Node SSH: ssh -p 30022 ubuntu@${PUBLIC_IP}  (via ~/.ssh/vmetal-demo/node-key)"
echo ""
echo "    Next: run 'make rack-connect' to connect rack-mgmt to the platform."
