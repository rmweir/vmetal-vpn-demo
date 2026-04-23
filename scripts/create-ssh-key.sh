#!/bin/bash
set -euo pipefail

# Creates an EC2 key pair named vmetal-rack-<iam-username> and saves the
# private key to ~/.ssh/vmetal-demo/ by default. If the key pair already exists in AWS
# and the private key is present locally, it is reused without changes.
#
# Progress output goes to stderr. Outputs SSH_KEY_NAME and SSH_KEY_FILE
# to stdout so callers can eval the result:
#
#   eval "$(./scripts/create-ssh-key.sh)"
#
# Usage:
#   ./scripts/create-ssh-key.sh
#   ./scripts/create-ssh-key.sh --region us-east-1

REGION="${REGION:-us-west-2}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --region) REGION="$2"; shift 2 ;;
    *) echo "Unknown argument: $1" >&2; exit 1 ;;
  esac
done

green()  { echo -e "\033[0;32m$*\033[0m" >&2; }
yellow() { echo -e "\033[0;33m$*\033[0m" >&2; }
red()    { echo -e "\033[0;31m$*\033[0m" >&2; }
info()   { echo "$*" >&2; }

# --- Prompt for SSH directory ---

read -rp "SSH key directory [~/.ssh/vmetal-demo]: " SSH_DIR < /dev/tty
SSH_DIR="${SSH_DIR:-$HOME/.ssh/vmetal-demo}"
SSH_DIR="${SSH_DIR/#\~/$HOME}"

# --- Derive key name from IAM username ---

info "==> Resolving IAM identity..."
IAM_USER=$(aws sts get-caller-identity --query 'Arn' --output text 2>/dev/null | awk -F'/' '{print $NF}') || {
  red "Could not resolve IAM identity. Check your AWS credentials."
  exit 1
}
KEY_NAME="vmetal-rack-${IAM_USER}"
KEY_FILE="${SSH_DIR}/${KEY_NAME}.pem"
info "    Key name: $KEY_NAME"
info "    Key file: $KEY_FILE"

# --- Check if key pair already exists in AWS ---

info "==> Checking for existing key pair in $REGION..."
EXISTS=$(aws ec2 describe-key-pairs \
  --key-names "$KEY_NAME" \
  --region "$REGION" \
  --query 'KeyPairs[0].KeyName' \
  --output text 2>/dev/null || echo "")

if [ "$EXISTS" = "$KEY_NAME" ]; then
  if [ -f "$KEY_FILE" ]; then
    green "    Key pair '$KEY_NAME' already exists and private key is at $KEY_FILE. Reusing."
    echo "SSH_KEY_NAME=${KEY_NAME}"
    echo "SSH_KEY_FILE=${KEY_FILE}"
    exit 0
  else
    yellow "    Key pair '$KEY_NAME' exists in AWS but private key not found at $KEY_FILE."
    yellow "    AWS does not store private keys — the old one cannot be recovered."
    read -rp "    Delete and recreate the key pair? [y/N] " answer < /dev/tty
    [[ "$answer" =~ ^[Yy]$ ]] || { info "Aborted."; exit 1; }
    info "==> Deleting existing key pair..."
    aws ec2 delete-key-pair --key-name "$KEY_NAME" --region "$REGION"
    green "    Deleted."
  fi
fi

# --- Create key pair and save private key ---

info "==> Creating key pair '$KEY_NAME' in $REGION..."
mkdir -p "$SSH_DIR"
chmod 700 "$SSH_DIR"
rm -f "$KEY_FILE"
aws ec2 create-key-pair \
  --key-name "$KEY_NAME" \
  --region "$REGION" \
  --query 'KeyMaterial' \
  --output text > "$KEY_FILE"
chmod 400 "$KEY_FILE"
green "    Private key saved to $KEY_FILE"

echo "SSH_KEY_NAME=${KEY_NAME}"
echo "SSH_KEY_FILE=${KEY_FILE}"
