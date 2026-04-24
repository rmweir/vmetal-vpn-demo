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

## Full demo setup

Run these in order — each step waits for the previous to complete:

```bash
make platform-start    # start vCluster Platform locally (prompts for license token)
make rack-provision    # provision rack EC2, deploy KubeVirt VMs + VirtualBMC
make rack-connect      # connect rack to platform as rack-mgmt, deploy Metal3
make cp-start          # provision CP node EC2, create vind cluster, register as metal-cp
make node-vcluster     # create the vCluster (privateNodes + VPN enabled)
make node-claim        # claim a bare metal node into the vCluster
```

## Credits

The `kubevirt/` directory is largely based on [loft-sh/vcluster-bare-metal-with-kubevirt](https://github.com/loft-sh/vcluster-bare-metal-with-kubevirt), which provides the KubeVirt VM definitions, VirtualBMC setup, bridge/CNI manifests, and Helm chart structure. This repo adapts that work for an external rack scenario: splitting rack and BareMetalHost deployment, switching VirtualBMC from in-cluster HTTPS to HTTP NodePorts, and adding iptables forwarding for external BMC access.

## Teardown

```bash
make cp-down      # destroy CP node EC2
make rack-down    # destroy rack EC2
```

To tear down the platform, delete the `platform-host` vind cluster:

```bash
vcluster --driver docker delete platform-host
```
