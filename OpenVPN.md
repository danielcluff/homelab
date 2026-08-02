# OpenVPN TAP Bridge for AppleTalk (SheepShaver)

L2 VPN bridge enabling AppleTalk discovery between Macs running SheepShaver (OS 9 emulation).

## Architecture

```
Mac 1 (SheepShaver) ─┐                    ┌─ OS 9 VM 1
                     ├── OpenVPN TAP ────►├── AppleTalk bridge
Mac 2 (SheepShaver) ─┘    (K8s pod)       └─ OS 9 VM 2
```

## IP Addressing

| Resource | IP |
|----------|-----|
| OpenVPN Server | 192.168.1.54 |
| VPN DHCP Pool | 192.168.1.80-99 |
| DNS Name | vpn.elate.me |

## Deployment

The manifest is already applied. Check status:

```bash
kubectl get all -n openvpn
kubectl get pvc -n openvpn
```

To redeploy:

```bash
kubectl apply -f manifests/openvpn-tap.yaml
```

## PKI Initialization (One-Time Setup)

The pod waits for PKI initialization before starting OpenVPN.

### 1. Enter the container

```bash
kubectl exec -it -n openvpn openvpn-tap-0 -- bash
```

### 2. Generate server configuration

```bash
ovpn_genconfig -t -u udp://vpn.elate.me -s 192.168.1.0/24 \
  -b -B 192.168.1.54 255.255.255.0 192.168.1.80 192.168.1.99
```

Flags:
- `-t` = TAP mode (L2, required for AppleTalk)
- `-u` = Server URL
- `-s` = Subnet
- `-b` = Enable bridging
- `-B` = Bridge parameters: server_ip netmask dhcp_start dhcp_end

### 3. Initialize PKI

```bash
ovpn_initpki
```

This will prompt for:
- CA passphrase (remember this for client certs)
- Common Name (press Enter for default)

### 4. Generate client certificates

```bash
easyrsa build-client-full mac1 nopass
easyrsa build-client-full mac2 nopass
```

Add more clients as needed with unique names.

### 5. Export client configurations

```bash
ovpn_getclient mac1 > /tmp/mac1.ovpn
ovpn_getclient mac2 > /tmp/mac2.ovpn
exit
```

### 6. Copy configs to local machine

```bash
kubectl cp openvpn/openvpn-tap-0:/tmp/mac1.ovpn ./mac1.ovpn
kubectl cp openvpn/openvpn-tap-0:/tmp/mac2.ovpn ./mac2.ovpn
```

### 7. Restart to start OpenVPN server

```bash
kubectl rollout restart statefulset/openvpn-tap -n openvpn
```

### 8. Verify server is running

```bash
kubectl logs -n openvpn openvpn-tap-0
```

You should see OpenVPN startup messages instead of "Sleeping..."

## Mac Client Setup

### Install Tunnelblick

1. Download from https://tunnelblick.net/
2. Install and open Tunnelblick

### Import VPN Configuration

1. Double-click the `.ovpn` file (mac1.ovpn or mac2.ovpn)
2. Tunnelblick will import it automatically
3. Click "Connect" on the VPN profile

### Verify Connection

After connecting, your Mac should get an IP in the 192.168.1.80-99 range:

```bash
ifconfig | grep -A5 tap
```

## SheepShaver Configuration

### Network Setup

1. In SheepShaver preferences, set network to use the TAP interface
2. The TAP interface is created by Tunnelblick when connected

### OS 9 AppleTalk Setup

1. Open **Control Panels > AppleTalk**
2. Set **Connect via:** to **Ethernet**
3. Restart if prompted

### Testing AppleTalk

1. Open **Chooser** (Apple menu)
2. Click **AppleShare** on the left
3. Other connected Macs should appear in the list

## Troubleshooting

### Check pod status

```bash
kubectl get pods -n openvpn
kubectl describe pod -n openvpn openvpn-tap-0
```

### Check logs

```bash
kubectl logs -n openvpn openvpn-tap-0
```

### Test UDP connectivity

From a Mac on the network:

```bash
nc -u 192.168.1.54 1194
```

### Verify LoadBalancer IP

```bash
kubectl get svc -n openvpn
```

Should show `EXTERNAL-IP: 192.168.1.54`

### Verify DNS resolution

```bash
nslookup vpn.elate.me 192.168.1.51
```

Should resolve to 192.168.1.54

### PKI issues

If you need to reinitialize PKI:

```bash
kubectl exec -it -n openvpn openvpn-tap-0 -- bash
rm -rf /etc/openvpn/*
# Then follow PKI initialization steps again
```

### Add more clients

```bash
kubectl exec -it -n openvpn openvpn-tap-0 -- bash
easyrsa build-client-full mac3 nopass
ovpn_getclient mac3 > /tmp/mac3.ovpn
exit
kubectl cp openvpn/openvpn-tap-0:/tmp/mac3.ovpn ./mac3.ovpn
```

## Technical Details

- **Image**: `salvoxia/openvpn-tap:latest`
- **Mode**: TAP (Layer 2) for AppleTalk/Ethernet bridging
- **Protocol**: UDP 1194
- **Network**: hostNetwork for direct UDP access
- **Storage**: 1Gi PVC for PKI/certificates
- **client-to-client**: Enabled for AppleTalk traffic between VPN clients
