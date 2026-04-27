# vMetal VPN Demo

Demonstrates vCluster Platform provisioning bare-metal nodes in a remote rack, with the provisioned nodes joining a Tenant Cluster via the platform VPN.

## Architecture

vCluster Platform connects to a remote rack via a relay cluster running the platform agent. Metal3 provisions bare-metal servers over Redfish, and once booted the servers join a Tenant Cluster through the platform VPN.

```mermaid
flowchart TD
    subgraph cloud["vCluster Platform (cloud / on-prem)"]
        plat["vCluster Platform"]
        metal3["Metal3 NodeProvider"]
        plat --- metal3
    end

    subgraph rack["Remote Rack (data center)"]
        relay["Relay Cluster\n(platform agent)"]
        tor["Top-of-Rack Switch"]
        relay --- tor
        subgraph bm1_box["Bare Metal Server 1"]
            bmc1["BMC\nRedfish / IPMI"]
            server1["Server 1"]
            bmc1 --> server1
        end
        subgraph bm2_box["Bare Metal Server 2"]
            bmc2["BMC\nRedfish / IPMI"]
            server2["Server 2"]
            bmc2 --> server2
        end
        tor --> bmc1 & bmc2
        tor --> server1 & server2
    end

    subgraph cp["Control Plane"]
        subgraph k8s["Kubernetes Cluster"]
            vci["Tenant Cluster\nprivateNodes + VPN"]
        end
    end

    plat -->|agent tunnel| relay
    plat -->|agent tunnel| k8s
    metal3 -->|Redfish provisioning| tor
    server1 & server2 -->|node join| plat
    plat -->|VPN| vci

    classDef platNode fill:#a5d8ff,stroke:#4a9eed,stroke-width:2px,color:#1e3a5f
    classDef provider fill:#d0bfff,stroke:#8b5cf6,stroke-width:2px,color:#2d1b69
    classDef relayNode fill:#eebefa,stroke:#8b5cf6,stroke-width:2px,color:#4a044e
    classDef torNode fill:#fff3bf,stroke:#f59e0b,stroke-width:2px,color:#7c3a00
    classDef bmc fill:#ffc9c9,stroke:#ef4444,stroke-width:2px,color:#7f1d1d
    classDef bm fill:#b2f2bb,stroke:#22c55e,stroke-width:2px,color:#14532d
    classDef vciNode fill:#b2f2bb,stroke:#22c55e,stroke-width:3px,color:#14532d

    class plat platNode
    class metal3 provider
    class relay relayNode
    class tor torNode
    class bmc1,bmc2 bmc
    class server1,server2 bm
    class vci vciNode

    style cloud fill:#dbe4ff,stroke:#4a9eed,stroke-width:2px,color:#1e3a5f
    style rack fill:#fff9db,stroke:#f59e0b,stroke-width:2px,color:#7c3a00
    style bm1_box fill:#ffd8a8,stroke:#f59e0b,stroke-width:1px,color:#7c3a00
    style bm2_box fill:#ffd8a8,stroke:#f59e0b,stroke-width:1px,color:#7c3a00
    style cp fill:#d3f9d8,stroke:#22c55e,stroke-width:2px,color:#14532d
    style k8s fill:#c3fae8,stroke:#22c55e,stroke-width:2px,color:#14532d
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
make node-vcluster     # create the vCluster — autoNodes provisions a bare metal node automatically
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

<details>
<summary>Demo setup (technical)</summary>

The demo simulates the above using EC2 instances and KubeVirt VMs instead of real hardware:

- **Bare metal servers** → KubeVirt VMs running inside a vind cluster on EC2
- **BMC (Redfish/IPMI)** → VirtualBMC exposed on HTTP NodePorts
- **Relay cluster** → `rack-mgmt` vind cluster on the rack EC2
- **Control plane cluster** → `metal-cp` vind cluster on a separate EC2

```mermaid
flowchart TD
    subgraph local["Local Machine"]
        platform["vCluster Platform\nplatform-host"]
        metal3["Metal3 NodeProvider"]
        platform --- metal3
    end

    subgraph rack["EC2 — Rack"]
        subgraph rack_vind["rack-mgmt  (vind cluster)"]
            vbmc["VirtualBMC — Redfish HTTP"]
            vm1["bare-metal-1\nKubeVirt VM"]
            vm2["bare-metal-2\nKubeVirt VM"]
            vbmc --> vm1 & vm2
        end
    end

    subgraph cp["EC2 — Control Plane"]
        subgraph cp_vind["metal-cp  (vind cluster)"]
            vci["metal-vcluster\nTenant Cluster\nprivateNodes + VPN"]
        end
    end

    platform -->|agent tunnel| rack_vind
    platform -->|agent tunnel| cp_vind
    metal3 -->|Redfish provisioning| vbmc
    vm1 & vm2 -->|node join| platform
    platform -->|VPN| vci

    classDef platNode fill:#a5d8ff,stroke:#4a9eed,stroke-width:2px,color:#1e3a5f
    classDef provider fill:#d0bfff,stroke:#8b5cf6,stroke-width:2px,color:#2d1b69
    classDef bmc fill:#ffc9c9,stroke:#ef4444,stroke-width:2px,color:#7f1d1d
    classDef vm fill:#b2f2bb,stroke:#22c55e,stroke-width:2px,color:#14532d
    classDef vciNode fill:#b2f2bb,stroke:#22c55e,stroke-width:3px,color:#14532d

    class platform platNode
    class metal3 provider
    class vbmc bmc
    class vm1,vm2 vm
    class vci vciNode

    style local fill:#dbe4ff,stroke:#4a9eed,stroke-width:2px,color:#1e3a5f
    style rack fill:#fff9db,stroke:#f59e0b,stroke-width:2px,color:#7c3a00
    style rack_vind fill:#ffd8a8,stroke:#f59e0b,stroke-width:2px,color:#7c3a00
    style cp fill:#d3f9d8,stroke:#22c55e,stroke-width:2px,color:#14532d
    style cp_vind fill:#c3fae8,stroke:#22c55e,stroke-width:2px,color:#14532d
```

</details>
