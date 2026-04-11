#!/bin/bash
set -euo pipefail

# Provisions the rack EC2 instance and bootstraps it with required tools,
# a vind cluster, KubeVirt, bridge networking, and CNI static plugin.
#
# Usage:
#   SSH_KEY_NAME=my-key ./scripts/provision-rack.sh
#
# Optional:
#   SSH_KEY_FILE  Path to private key (default: ~/.ssh/$SSH_KEY_NAME.pem)
#   REGION        AWS region (default: us-west-2)

SSH_KEY_NAME="${SSH_KEY_NAME:?SSH_KEY_NAME is required}"
SSH_KEY_FILE="${SSH_KEY_FILE:-$HOME/.ssh/${SSH_KEY_NAME}.pem}"
REGION="${REGION:-us-west-2}"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

ssh_cmd() {
  ssh -i "$SSH_KEY_FILE" -o StrictHostKeyChecking=no ubuntu@"$PUBLIC_IP" "$@"
}

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
echo "    vind cluster IP: $VIND_IP"
ssh_cmd "sudo sysctl -w net.ipv4.ip_forward=1"
ssh_cmd "sudo iptables -t nat -A PREROUTING -p tcp --dport 30443 -j DNAT --to-destination ${VIND_IP}:30443"
ssh_cmd "sudo iptables -t nat -A PREROUTING -p tcp --dport 30444 -j DNAT --to-destination ${VIND_IP}:30444"
ssh_cmd "sudo iptables -t nat -A POSTROUTING -d ${VIND_IP} -j MASQUERADE"
ssh_cmd "sudo iptables -I FORWARD 1 -p tcp -d ${VIND_IP} --dport 30443 -j ACCEPT"
ssh_cmd "sudo iptables -I FORWARD 1 -p tcp -d ${VIND_IP} --dport 30444 -j ACCEPT"
ssh_cmd "sudo iptables -I FORWARD 1 -p tcp -s ${VIND_IP} -j ACCEPT"

echo ""
echo "==> Rack is ready"
echo "    SSH: ssh -i $SSH_KEY_FILE ubuntu@$PUBLIC_IP"
