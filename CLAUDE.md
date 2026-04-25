# vmetal-vpn-demo

End-to-end demo: vCluster Platform provisions KubeVirt VMs on a remote EC2 rack as bare-metal nodes, which join a Tenant Cluster on a separate EC2 via the platform VPN.

## Architecture

- **Local machine** — vCluster Platform (`vcluster platform start`), Metal3 NodeProvider
- **EC2 rack** — vind cluster running KubeVirt VMs + VirtualBMC (Redfish over HTTP NodePorts); connected to platform as `rack-mgmt` agent
- **EC2 CP node** — vind cluster registered as `metal-cp`; hosts the Tenant Cluster (`metal-vcluster`)
- **Tenant Cluster** — privateNodes + VPN enabled; bare metal nodes join via the platform tunnel

## Key repos

- `loft-sh/loft-enterprise` — platform nodeclaim controller (`pkg/controllers/nodeclaim/controller.go`); checks `vcluster.loft.sh/kubernetes-name` annotation to determine if a node has joined
- `loft-sh/vcluster-pro` — `InitNodeController` (`pkg/privatenodes/autonodes/controllers/initnode.go`); runs inside the Tenant Cluster, sets the `kubernetes-name` annotation on the platform NodeClaim when a node joins; Karpenter cloud provider (`pkg/privatenodes/autonodes/karpenter/cloudprovider/cloudprovider.go`) creates NodeClaims with the uid label needed for InitNodeController to find them

## NodeClaim approach

The demo uses `autoNodes` (configured in `manifests/metal-vcluster.yaml`), not manual NodeClaims. Do not create NodeClaims directly — nodes will never be marked as joined (ENGPLAT-477).

## macOS compatibility

Some scripts use `grep -oP` (Perl regex) which is not available on macOS BSD grep. If running on macOS, these will need to be updated (e.g. use `grep -oE` or install GNU grep via Homebrew).
