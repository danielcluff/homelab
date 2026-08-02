# Add Node to Talos Cluster

Add a new worker node to the homelab Talos Kubernetes cluster with Longhorn storage support.

## ⚠️ CRITICAL: Custom Talos Image Required

**DO NOT use the default Talos ISO.** Longhorn requires iSCSI extensions that are NOT included in the standard Talos image. You MUST boot the node from a custom Talos image built with the required extensions.

**Required Extensions:**
- `siderolabs/iscsi-tools` - iSCSI initiator for Longhorn storage (REQUIRED)
- `siderolabs/util-linux-tools` - Storage utilities including fstrim for SSD TRIM (REQUIRED)

**Download the custom ISO before starting:**
```bash
# Download custom Talos ISO with Longhorn extensions
curl -LO "https://factory.talos.dev/image/c9078f9419961640c712a8bf2bb9174933dfcf1da383fd8ea2b7dc21493f8bac/v1.11.6/metal-amd64.iso"

# Flash to USB drive (replace /dev/sdX with your USB device)
# sudo dd if=metal-amd64.iso of=/dev/sdX bs=4M status=progress
```

Boot the new node from this ISO, NOT from the standard Talos ISO.

---

## Arguments

This skill accepts the following arguments:
- `$ARGUMENTS` - Should contain: `<current_ip> <target_ip>` (e.g., `192.168.1.116 192.168.1.42`)

Parse the arguments:
- **Current IP**: The node's current IP address (where Talos will be applied)
- **Target IP**: The desired static IP address for the node after joining

If arguments are not provided or invalid, ask the user for:
1. The current IP address of the node (where it can be reached now)
2. The desired static IP address for the node

## Prerequisites

Before proceeding, verify:
1. **The node was booted from the custom Talos ISO** (not the default one)
2. These tools are available:

```bash
# Check talosctl is installed
talosctl version --client

# Check kubectl is configured
kubectl get nodes
```

## Cluster Configuration Reference

Use these values from the existing cluster:
- **Control Plane Endpoint**: `https://192.168.1.41:6443`
- **Gateway**: `192.168.1.1`
- **DNS**: `192.168.1.1`
- **Network Interface**: `enp2s0`
- **Install Disk**: `/dev/nvme0n1`
- **Cluster Name**: `homelab`

## Step 1: Verify Custom Talos Image (or Build One)

**IMPORTANT:** If you skipped the critical section above and booted from the default Talos ISO, STOP. You have two options:
1. Re-image the node with the custom ISO (recommended for fresh installs)
2. Continue and upgrade the node to the custom image after applying config (works but takes longer)

### Current Cluster Schematic

The cluster uses this custom schematic with Longhorn extensions:
```
Schematic ID: c9078f9419961640c712a8bf2bb9174933dfcf1da383fd8ea2b7dc21493f8bac
Talos Version: v1.11.6
Extensions: siderolabs/iscsi-tools, siderolabs/util-linux-tools

ISO URL: https://factory.talos.dev/image/c9078f9419961640c712a8bf2bb9174933dfcf1da383fd8ea2b7dc21493f8bac/v1.11.6/metal-amd64.iso
Installer: factory.talos.dev/installer/c9078f9419961640c712a8bf2bb9174933dfcf1da383fd8ea2b7dc21493f8bac:v1.11.6
```

### Required Kernel Modules (configured in machine config)
- `nbd` - Network block device
- `iscsi_tcp` - iSCSI TCP transport
- `iscsi_generic` - Generic iSCSI support
- `configfs` - Configuration filesystem

### Generate New Schematic (only if upgrading Talos version)

If you need a new schematic (e.g., for a newer Talos version):

1. Go to https://factory.talos.dev/
2. Select the desired Talos version
3. Select **System Extensions** - YOU MUST SELECT BOTH:
   - `siderolabs/iscsi-tools` (REQUIRED for Longhorn)
   - `siderolabs/util-linux-tools` (REQUIRED for storage utilities)
4. Click **Generate** to get the schematic ID
5. Update this document and the cluster configs with the new schematic ID
6. Download the new ISO and installer URLs

## Step 2: Verify Node Accessibility

Check that the node is reachable at the current IP:

```bash
ping -c 3 <CURRENT_IP>
```

If the node is in Talos maintenance mode (booted from ISO), check:

```bash
talosctl --nodes <CURRENT_IP> disks --insecure
```

## Step 3: Create Worker Configuration

Create the patches directory:

```bash
mkdir -p talos-patches
```

Create the patch file `talos-patches/worker-<TARGET_IP>.yaml`:

```yaml
machine:
  kernel:
    modules:
      - name: nbd
      - name: iscsi_tcp
      - name: iscsi_generic
      - name: configfs
  network:
    interfaces:
      - interface: enp2s0
        dhcp: false
        addresses:
          - <TARGET_IP>/24
        routes:
          - network: 0.0.0.0/0
            gateway: 192.168.1.1
    nameservers:
      - 192.168.1.1
  install:
    disk: /dev/nvme0n1
    image: factory.talos.dev/installer/c9078f9419961640c712a8bf2bb9174933dfcf1da383fd8ea2b7dc21493f8bac:v1.11.6
    wipe: true
  sysctls:
    net.ipv4.conf.all.arp_announce: "0"
    net.ipv4.conf.all.arp_ignore: "0"
    net.ipv4.ip_forward: "1"
```

Replace `<TARGET_IP>` with the actual target IP address (e.g., `192.168.1.42`).

**Important Notes**:
- `wipe: true` will erase the disk - use `wipe: false` if upgrading an existing Talos installation
- The `image` URL uses the custom factory image with iscsi-tools and util-linux-tools extensions
- Adjust `interface: enp2s0` if the new node has a different network interface name

## Step 4: Generate Final Worker Configuration

Apply the patch to the existing worker.yaml (which contains cluster secrets):

```bash
# Patch the existing worker config with our customizations
talosctl machineconfig patch worker.yaml \
    --patch @talos-patches/worker-<TARGET_IP>.yaml \
    --output talos-patches/worker-<TARGET_IP>-final.yaml
```

## Step 5: Verify Configuration

Before applying, verify the critical settings:

```bash
# Check kernel modules
echo "=== Kernel Modules ==="
grep -A 6 "kernel:" talos-patches/worker-<TARGET_IP>-final.yaml

# Check network configuration
echo "=== Network Config ==="
grep -A 12 "interfaces:" talos-patches/worker-<TARGET_IP>-final.yaml

# Check install image (must be factory.talos.dev URL)
echo "=== Install Image ==="
grep "image:" talos-patches/worker-<TARGET_IP>-final.yaml | grep -v "#"

# Check cluster secrets are present
echo "=== Cluster Config ==="
grep "endpoint:" talos-patches/worker-<TARGET_IP>-final.yaml
```

Verify:
- Install image uses `factory.talos.dev/installer/...` (not `ghcr.io/siderolabs/installer`)
- Kernel modules include: nbd, iscsi_tcp, iscsi_generic, configfs
- Network config shows the correct target IP
- Control plane endpoint is `https://192.168.1.41:6443`

## Step 6: Apply Configuration to Node

Apply the configuration to the node:

```bash
talosctl apply-config \
    --nodes <CURRENT_IP> \
    --file talos-patches/worker-<TARGET_IP>-final.yaml \
    --insecure
```

**Note**: Use `--insecure` for nodes in maintenance mode (fresh installation). The node will:
1. Write configuration to disk
2. Install Talos with the custom image
3. Reboot with the new IP address

## Step 7: Wait for Node to Come Online

After the node reboots, it will use the new static IP address. Wait for it:

```bash
echo "Waiting for node at <TARGET_IP>..."
for i in {1..60}; do
    if ping -c 1 -W 1 <TARGET_IP> >/dev/null 2>&1; then
        echo "Node is reachable at <TARGET_IP>"
        break
    fi
    echo -n "."
    sleep 5
done

# Add the new node to talosconfig endpoints
talosctl --talosconfig=./talosconfig config endpoints 192.168.1.41 <TARGET_IP>
```

Check Talos status:

```bash
talosctl --talosconfig=./talosconfig --nodes <TARGET_IP> version
```

## Step 8: Verify Extensions and Modules

Confirm the custom image was installed with required extensions:

```bash
# Check installed extensions
talosctl --talosconfig=./talosconfig --nodes <TARGET_IP> get extensions

# Expected output should include:
# - siderolabs/iscsi-tools
# - siderolabs/util-linux-tools
```

Verify kernel modules are loaded:

```bash
talosctl --talosconfig=./talosconfig --nodes <TARGET_IP> read /proc/modules | grep -E "(nbd|iscsi|configfs)"
```

Check iSCSI service is available:

```bash
talosctl --talosconfig=./talosconfig --nodes <TARGET_IP> services | grep -i iscsi
```

## Step 9: Verify Cluster Join

Check that the node has joined the Kubernetes cluster:

```bash
# Watch for the new node to appear
kubectl get nodes -w

# Check node details
kubectl get nodes -o wide
```

The node should appear as `Ready` within a few minutes.

## Step 10: Post-Join Configuration

### Verify Longhorn Can Use the Node

Check that Longhorn recognizes the new node:

```bash
kubectl get nodes.longhorn.io -n longhorn-system
```

### Update Longhorn Replica Count (if 3+ nodes)

If you now have 3 or more nodes, increase Longhorn's replica count for redundancy:

```bash
kubectl patch -n longhorn-system settings.longhorn.io default-replica-count \
    -p '{"value":"3"}' --type=merge
```

### Update MetalLB (if first worker node)

If this is the first worker node added to a single control-plane cluster, update MetalLB to follow Kubernetes best practices:

```bash
# Revert MetalLB to respect control plane exclusion label
helm upgrade metallb metallb/metallb -n metallb-system \
    --set speaker.ignoreExcludeLB=false \
    --reuse-values

# Wait for speaker to restart
kubectl rollout status daemonset/metallb-speaker -n metallb-system
```

**Important**: Only do this after the worker node is Ready and workloads can be scheduled on it.

### Update Pi-hole DNS (optional)

Add a DNS entry for the new node in Pi-hole if needed for management.

## Troubleshooting

### Node booted from default Talos ISO (missing extensions)

If you see errors like `error loading module iscsi_generic: module not found` or `get extensions` doesn't show iscsi-tools, the node was booted from the default ISO instead of the custom one.

**Fix:** Upgrade the node to the custom image:
```bash
talosctl --talosconfig=./talosconfig --nodes <TARGET_IP> upgrade \
  --image factory.talos.dev/installer/c9078f9419961640c712a8bf2bb9174933dfcf1da383fd8ea2b7dc21493f8bac:v1.11.6
```

Wait for the node to reboot, then verify extensions:
```bash
talosctl --talosconfig=./talosconfig --nodes <TARGET_IP> get extensions
# Should show: siderolabs/iscsi-tools and siderolabs/util-linux-tools
```

### "exec format error" or missing extensions

The installer image doesn't have the required extensions. Ensure you're using the factory.talos.dev URL:

```bash
grep "image:" talos-patches/worker-<TARGET_IP>-final.yaml
# Should show: factory.talos.dev/installer/c9078f9419961640c712a8bf2bb9174933dfcf1da383fd8ea2b7dc21493f8bac:v1.11.6
```

If using `ghcr.io/siderolabs/installer`, regenerate the config with the factory image.

### Longhorn volumes not mounting

Check iSCSI is working:

```bash
# On the node
talosctl --talosconfig=./talosconfig --nodes <TARGET_IP> services | grep ext-
# Should show ext-iscsid and ext-tgtd running
```

### Node not reachable after reboot

1. Wait 2-5 minutes for full boot
2. Verify the network interface name matches (check `ip link` from ISO boot)
3. Check physical network connection
4. Connect to console to see boot logs

### Node not joining cluster

Check Talos logs:

```bash
talosctl --talosconfig=./talosconfig --nodes <TARGET_IP> logs kubelet
talosctl --talosconfig=./talosconfig --nodes <TARGET_IP> logs etcd 2>/dev/null || echo "Not a control plane"
```

Common issues:
- Time sync issues (check NTP)
- Network connectivity to control plane
- Cluster token mismatch (ensure using existing worker.yaml secrets)

### Kernel modules not loaded

```bash
talosctl --talosconfig=./talosconfig --nodes <TARGET_IP> read /proc/modules | grep -E "(nbd|iscsi|configfs)"
```

If empty, check the config was applied correctly:

```bash
talosctl --talosconfig=./talosconfig --nodes <TARGET_IP> get machineconfig -o yaml | grep -A 6 "kernel:"
```

## Summary

After completing all steps, you should have:
- A new worker node at `<TARGET_IP>` with static IP
- Custom Talos image with iscsi-tools and util-linux-tools extensions
- Kernel modules loaded: nbd, iscsi_tcp, iscsi_generic, configfs
- Node visible in `kubectl get nodes` as Ready
- Longhorn storage support fully functional

The node is now part of your homelab cluster and ready to run workloads with persistent storage.
