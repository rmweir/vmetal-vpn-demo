#!/bin/bash
set -euo pipefail

# Local setup script for vmetal-vpn-demo.
# Checks for required tools and offers to install any that are missing.

OS="$(uname -s)"
ARCH="$(uname -m)"

green() { echo -e "\033[0;32m$*\033[0m"; }
yellow() { echo -e "\033[0;33m$*\033[0m"; }
red() { echo -e "\033[0;31m$*\033[0m"; }

check() {
  local name="$1"
  local cmd="$2"
  if command -v "$cmd" &>/dev/null; then
    green "  [ok] $name ($(command -v "$cmd"))"
    return 0
  else
    yellow "  [missing] $name"
    return 1
  fi
}

ask_install() {
  local name="$1"
  read -rp "Install $name? [y/N] " answer
  [[ "$answer" =~ ^[Yy]$ ]]
}

# --- OpenTofu ---

install_tofu() {
  echo "Installing OpenTofu..."
  if [ "$OS" = "Darwin" ]; then
    if command -v brew &>/dev/null; then
      brew install opentofu
    else
      red "Homebrew not found. Install it from https://brew.sh then re-run this script."
      exit 1
    fi
  elif [ "$OS" = "Linux" ]; then
    local version
    version=$(curl -fsSL https://api.github.com/repos/opentofu/opentofu/releases/latest | grep '"tag_name"' | sed 's/.*"v\([^"]*\)".*/\1/')
    local bin_arch
    case "$ARCH" in
      x86_64)  bin_arch="amd64" ;;
      aarch64) bin_arch="arm64" ;;
      *)       red "Unsupported architecture: $ARCH"; exit 1 ;;
    esac
    curl -fsSL "https://github.com/opentofu/opentofu/releases/download/v${version}/tofu_${version}_linux_${bin_arch}.zip" -o /tmp/tofu.zip
    unzip -q /tmp/tofu.zip tofu -d /tmp
    sudo mv /tmp/tofu /usr/local/bin/tofu
    rm /tmp/tofu.zip
  else
    red "Unsupported OS: $OS"
    exit 1
  fi
}

# --- AWS CLI ---

install_awscli() {
  echo "Installing AWS CLI..."
  if [ "$OS" = "Darwin" ]; then
    if command -v brew &>/dev/null; then
      brew install awscli
    else
      red "Homebrew not found. Install it from https://brew.sh then re-run this script."
      exit 1
    fi
  elif [ "$OS" = "Linux" ]; then
    local zip_arch
    case "$ARCH" in
      x86_64)  zip_arch="x86_64" ;;
      aarch64) zip_arch="aarch64" ;;
      *)       red "Unsupported architecture: $ARCH"; exit 1 ;;
    esac
    curl -fsSL "https://awscli.amazonaws.com/awscli-exe-linux-${zip_arch}.zip" -o /tmp/awscliv2.zip
    unzip -q /tmp/awscliv2.zip -d /tmp
    sudo /tmp/aws/install
    rm -rf /tmp/awscliv2.zip /tmp/aws
  else
    red "Unsupported OS: $OS"
    exit 1
  fi
}

# --- Main ---

echo ""
echo "Checking required tools..."
echo ""

missing=()

check "OpenTofu" "tofu"  || missing+=("tofu")
check "AWS CLI" "aws"    || missing+=("aws")

echo ""

if [ ${#missing[@]} -eq 0 ]; then
  green "All tools are installed."
  exit 0
fi

echo "The following tools are missing: ${missing[*]}"
echo ""

for tool in "${missing[@]}"; do
  if ask_install "$tool"; then
    case "$tool" in
      tofu) install_tofu ;;
      aws)  install_awscli ;;
    esac
    echo ""
  fi
done

echo ""
echo "Done. Re-run this script to verify."
