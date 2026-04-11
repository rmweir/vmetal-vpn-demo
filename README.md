# vMetal VPN Demo

Demonstrates vCluster Platform provisioning KubeVirt VMs on a remote EC2 "rack" as bare-metal nodes, with the provisioned nodes joining a vCluster control plane on a separate EC2 via the platform VPN.

## Architecture

```
Local machine
└── vCluster Platform (vcluster platform start → public tunnel URL)
    └── NodeProvider → Metal3 → VirtualBMC

EC2 #1 — rack
└── vind cluster (k3s in Docker)
    ├── KubeVirt VMs (bare-metal-1, bare-metal-2)
    └── VirtualBMC (Redfish HTTP on NodePorts 30443, 30444)
        └── reachable externally via iptables DNAT

EC2 #2 — control plane
└── vCluster (privateNodes + VPN enabled)
    └── provisioned VMs join here via platform tunnel URL
```

## Prerequisites

- AWS credentials configured (`aws configure` or environment variables)
- An EC2 key pair; set `SSH_KEY_NAME` and `SSH_KEY_FILE` accordingly
- [OpenTofu](https://opentofu.org) — run `./scripts/setup.sh` to install
- [vcluster CLI](https://www.vcluster.com/docs/vcluster/next/getting-started/install-vcluster-cli)

## Rack setup

Provision the rack EC2 (creates the instance, bootstraps tools, deploys KubeVirt VMs and VirtualBMC):

```bash
make rack-provision SSH_KEY_NAME=<key-pair-name> SSH_KEY_FILE=~/.ssh/<key>.pem
```

By default this uses a `c5.metal` instance in `us-west-2`. Override with:

```bash
make rack-provision SSH_KEY_NAME=... SSH_KEY_FILE=... \
  INSTANCE_TYPE=c5.metal REGION=us-east-1
```

After provisioning, the VirtualBMC Redfish endpoints are reachable at:

| VM | BMC address |
|----|-------------|
| bare-metal-1 | `redfish+http://<rack-ip>:30443` |
| bare-metal-2 | `redfish+http://<rack-ip>:30444` |

Get the rack IP:

```bash
make rack-ip
```

SSH into the rack:

```bash
make rack-ssh SSH_KEY_NAME=... SSH_KEY_FILE=...
```

## Platform setup

Start vCluster Platform locally (exposes a public tunnel URL):

```bash
vcluster platform start
```

Then:
1. Connect EC2 #2 to the platform as a cluster
2. Create a NodeProvider pointing Metal3 at the rack's BMC endpoints above
3. Create a vCluster on EC2 #2 with `privateNodes` and VPN enabled
4. Add servers via the platform UI — Metal3 provisions the VMs, nodes join the vCluster over the VPN

## Credits

The `kubevirt/` directory is largely based on [loft-sh/vcluster-bare-metal-with-kubevirt](https://github.com/loft-sh/vcluster-bare-metal-with-kubevirt), which provides the KubeVirt VM definitions, VirtualBMC setup, bridge/CNI manifests, and Helm chart structure. This repo adapts that work for an external rack scenario: splitting rack and BareMetalHost deployment, switching VirtualBMC from in-cluster HTTPS to HTTP NodePorts, and adding iptables forwarding for external BMC access.

## Teardown

```bash
make rack-down SSH_KEY_NAME=... SSH_KEY_FILE=...
```
