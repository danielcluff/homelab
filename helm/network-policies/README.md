# Homelab network policies

This chart owns namespace security classifications and the staged policy
rollout. Most managed namespaces are enforced. An `observe` namespace has a
`staged-allow-all` Kubernetes NetworkPolicy so traffic can be audited before
explicit allow rules replace it.

## Classifications

- `infrastructure`: cluster controllers, ingress, storage, and monitoring.
- `internal`: applications reachable only from the LAN or Tailscale.
- `public`: applications reachable through Cloudflare Tunnel and the isolated public ingress path.

System namespaces are excluded until their host, API-server, DNS, Hubble, and
storage dependencies have dedicated Cilium policies.

## Deployment

```bash
helm upgrade --install network-policies helm/network-policies \
  --namespace kube-system \
  --take-ownership \
  --force-conflicts
```

Namespace resources have `helm.sh/resource-policy: keep`; uninstalling this
chart must never delete application namespaces.

## Moving a namespace to enforcement

1. Observe representative traffic in Hubble, including application startup,
   backups, certificate renewal, monitoring, and ingress requests.
2. Add explicit ingress and egress policies for DNS, Traefik, monitoring,
   required peers, and external destinations.
3. Render and review the chart.
4. Change the namespace mode only after its allow rules are present.
5. Validate the service from LAN and Tailscale before moving to the next
   namespace.

Never move `longhorn-system`, `kube-system`, `traefik`, or `monitoring` to
default deny as the first enforcement target.

## Enforced namespaces

### Cloudflare Tunnel gateway

The `cloudflare-tunnel` namespace is classified `public` and begins in a
fail-closed state. Its connector may resolve DNS and establish outbound
Cloudflare connections on TCP/UDP 7844, but it has no egress path to any
application namespace. This means a mistaken remotely managed tunnel route
cannot reach an existing internal service.

Cloudflared may reach only the isolated public Traefik controller. Never add a
broad `cluster` egress rule, direct application egress, or a route to the
internal Traefik controller, since any of these would bypass the
internal/public service boundary.

The dedicated `traefik-public` controller provides Kubernetes Ingress for public
applications. cloudflared may reach only that controller's TCP/8000 entrypoint,
and the controller starts with no application-backend egress. Each backend
requires an exact selector and port in both directions before its Cloudflare
route can be migrated. The controller is ClusterIP-only, watches only listed
public namespaces, uses the non-default `traefik-public` IngressClass, and has
no dashboard or CRD provider.

The `elate-me` and `elate-biz` workloads are routed through the isolated public
Traefik controller. cloudflared has no direct application-backend egress. Each
site accepts only the exact public-Traefik workload and node health probes on
TCP/8080, and both site pods have all egress denied.

### Heimdall

Heimdall is the first enforced namespace. Its Cilium policy allows:

- ingress from Traefik to TCP/80;
- node-originated TCP/80 health probes;
- DNS through CoreDNS over UDP/TCP 53;
- outbound HTTP/HTTPS to the internet and `192.168.1.0/24`.

All other Heimdall ingress and egress is denied. To roll back immediately, set
Heimdall's `mode` to `observe` in `values.yaml` and run the Helm upgrade; this
removes `heimdall-enforced` and restores `staged-allow-all`.

### Registry

The registry policy allows TCP/5000 from Traefik, cluster nodes, and clients
forwarded through its private MetalLB address `192.168.1.53`. MetalLB traffic
can be identified as `world` after node SNAT, so `world` is allowed only on the
registry port. The address remains LAN-only at the network perimeter. Registry
egress is restricted to CoreDNS.

To roll back, set the registry's `mode` to `observe` and upgrade the chart.

### Uptime Kuma

Uptime Kuma accepts TCP/3001 from Traefik and node health probes. Its egress is
limited to CoreDNS, HTTPS through Traefik, Prometheus TCP/9090, Alertmanager
TCP/9093, the translated Pi-hole HTTPS endpoint, HTTPS on the home LAN, and
public HTTPS for the apex `elate.me` monitor. No notification providers are
currently configured.

Six monitor failures predate policy enforcement: duplicate Heimdall checks,
duplicate Pi-hole checks, and the AutoMaker UI/API checks. Use the existing
failure set as the baseline when validating policy changes.

To roll back, set Uptime Kuma's `mode` to `observe` and upgrade the chart.

### cert-manager

The cert-manager policy permits Prometheus metrics on TCP/9402, node health
probes on TCP/6080 and TCP/9403, and API-server webhook calls on TCP/10250.
Egress is limited to CoreDNS, the Kubernetes API on TCP/6443, and public HTTPS
for ACME and Cloudflare DNS-01 operations.

To roll back, set cert-manager's mode to `observe` and upgrade the chart.

### Pi-hole

Pi-hole accepts TCP/UDP 53 only from configured household client CIDRs and
node-forwarded MetalLB traffic. The list includes the LAN, Tailscale, and the
currently observed household WAN `/32`, because router NAT presents local DNS
queries with that address. Update `pihole.allowedDnsClientCIDRs` if the WAN IP
changes. DHCP discovery remains allowed on UDP/67.

Web administration is restricted to Traefik on TCP/80. The Uptime Kuma
TCP/443 probe is retained to preserve its existing connection-refused baseline.
Egress is limited to DNS through `1.1.1.1` and `8.8.8.8`, plus public HTTP,
HTTPS, and NTP for gravity and update operations.

To roll back, set Pi-hole's mode to `observe` and upgrade the chart.

### Development namespaces

Both code-server instances accept ingress only from Traefik. They may use
CoreDNS, public Git/web endpoints, internal HTTPS through Traefik, and the
private registry. Only the `environment=homelab` instance may reach the
Kubernetes API on TCP/6443.

Future DevPod workspace pods have no permitted ingress. Their egress is limited
to DNS, public Git/web endpoints, the private registry, and the Kubernetes API.
Set the corresponding namespace mode back to `observe` for rollback.

### Host-network VPN workloads

OpenVPN and Tailscale intentionally remain in `observe`. Both pods use
`hostNetwork: true`, share their Talos node's network namespace, and do not
have ordinary Cilium pod endpoints. Namespaced Cilium policies therefore
cannot isolate them. Cilium host firewall is currently disabled; enabling it
would affect the complete node and requires a separate host-policy design for
Kubernetes, Talos management, storage, VPN, and LAN traffic.

OpenVPN is disabled by default with `replicaCount: 0` in its Helm chart. Its
PKI PVC and LoadBalancer service remain available for occasional Mac OS 9 use.
Temporarily enable it with `--set replicaCount=1`, then explicitly restore
`--set replicaCount=0` afterward because Helm retains command-line values.

Do not change these namespaces to `enforce` until either the workloads are
moved off host networking or a tested node-level firewall policy is ready.

### Monitoring

Monitoring uses workload-specific rules: Grafana can reach only its Prometheus
and Alertmanager datasources; kube-state-metrics can reach the Kubernetes API;
Prometheus can reach the API, observed node/Cilium metrics, CoreDNS,
cert-manager, Traefik, and its in-namespace scrape targets. Alertmanager allows
HTTPS notifications, while Pushgateway accepts metric pushes from the cluster.

Node exporter remains a host-network exception and is protected by the LAN and
node boundary rather than namespaced endpoint policy. Roll back by changing
monitoring to `observe` and upgrading the chart.

### Traefik

Traefik accepts frontend traffic only on TCP/80 and TCP/443, node probes on
TCP/8080, and Prometheus on TCP/9100. Egress is limited to CoreDNS, the
Kubernetes API, and explicitly selected backends for every current Ingress.
Adding a new Ingress requires adding its backend selector and target port here.

The insecure admin API and global backend TLS-verification bypass are disabled
in the Traefik Helm values. Roll back network enforcement by changing Traefik
to `observe`; do not restore either insecure argument.

### Longhorn

Longhorn permits unrestricted pod-to-pod traffic only within
`longhorn-system`. This is required because instance managers allocate engine
and replica ports dynamically, including TCP/10000-30000. Cross-namespace
access is restricted to Traefik reaching the UI on TCP/8000 and Prometheus
scraping manager metrics on TCP/9500. Node identities may reach only the API
webhooks, health probe, iSCSI, and NFS ports required for storage operations.

Egress is limited to other Longhorn components, CoreDNS, the Kubernetes API,
and public HTTPS for version checks and optional HTTPS backup targets. If a
non-HTTPS backup target is configured later, add its exact destination and
port before enabling it. Roll back by changing Longhorn's mode to `observe`
and upgrading the chart.

### MetalLB

The MetalLB controller is enforced independently. It accepts node-originated
health probes on TCP/7472 and API-server admission webhook calls on TCP/9443;
its egress is limited to CoreDNS and the Kubernetes API. It does not require a
direct network connection to the speakers because both components coordinate
through Kubernetes resources.

MetalLB speakers use `hostNetwork: true` so this namespaced policy cannot
isolate their ARP announcements, TCP/UDP 7946 memberlist traffic, or FRR
processes. Those remain protected by the Talos node and LAN boundary. Do not
describe the speakers as policy-enforced unless Cilium host firewall is later
enabled and tested for the entire node. Roll back controller enforcement by
changing MetalLB's mode to `observe` and upgrading the chart.

helm upgrade openvpn helm/openvpn -n openvpn --set replicaCount=1

helm upgrade openvpn helm/openvpn -n openvpn --set replicaCount=0
