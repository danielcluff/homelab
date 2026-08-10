# Monitoring Setup Guide

This guide explains how to programmatically configure Grafana datasources and Uptime Kuma monitors.

## Grafana Datasource Provisioning

### Overview

Grafana datasources are automatically configured using Kubernetes ConfigMaps. The datasources are loaded on pod startup.

### Current Configuration

**Location**: `helm/grafana/templates/grafana-datasources.yaml`

**Configured Datasources**:

-   **Prometheus** - `http://prometheus-server.monitoring.svc.cluster.local` (default)
-   **Alertmanager** - `http://prometheus-alertmanager.monitoring.svc.cluster.local:9093`

### How It Works

1. ConfigMap `grafana-datasources` contains datasource definitions
2. ConfigMap is mounted to `/etc/grafana/provisioning/datasources/` in Grafana pod
3. Grafana automatically loads datasources on startup
4. Changes to ConfigMap require pod restart: `kubectl rollout restart deployment grafana -n monitoring`

### Adding New Datasources

Edit `helm/grafana/templates/grafana-datasources.yaml` and add to the `datasources` list:

```yaml
- name: My New Source
  type: prometheus # or influxdb, mysql, postgres, etc.
  access: proxy
  url: http://my-service.namespace.svc.cluster.local:9090
  isDefault: false
  editable: true
```

Then apply and restart:

```bash
helm upgrade grafana helm/grafana -n monitoring
kubectl rollout restart deployment grafana -n monitoring
```

### Verifying Datasources

**Via UI**: https://grafana.elate.me → Configuration → Data sources

**Via API**:

```bash
read -r "GRAFANA_USERNAME?Grafana username: "
read -s "GRAFANA_PASSWORD?Grafana password: "
echo
curl -u "$GRAFANA_USERNAME:$GRAFANA_PASSWORD" https://grafana.elate.me/api/datasources | jq
unset GRAFANA_PASSWORD
```

**Via kubectl**:

```bash
kubectl exec -n monitoring deployment/grafana -- \
  curl -s http://localhost:3000/api/datasources | jq
```

---

## Uptime Kuma Monitor Setup

### Overview

Uptime Kuma monitors are configured via API using a bash script. The script must be run after initial setup.

### First-Time Setup

1. **Complete initial Uptime Kuma setup manually**:

    - Visit https://uptime.elate.me
    - Create your admin account
    - Note your username and password

2. **Run the setup script**:
    ```bash
    cd /Users/daniel/dev/homelab
    UPTIME_KUMA_USERNAME=admin UPTIME_KUMA_PASSWORD=password ./scripts/setup-uptime-kuma.sh
    ```

### What Gets Configured

The script creates monitors for:

**External Services (HTTPS)**:

-   Heimdall Dashboard (elate.me)
-   Grafana (grafana.elate.me)
-   Longhorn UI (longhorn.elate.me)
-   Pi-hole Admin (pihole.elate.me)
-   Traefik Dashboard (traefik.elate.me)
-   Dev Environment (dev.elate.me)
-   HomeLab Environment (homelab.elate.me)

**Internal Services (HTTP)**:

-   Prometheus Server
-   Alertmanager

### Customizing Monitors

Edit `scripts/setup-uptime-kuma.sh` and modify the `create_monitor` calls:

```bash
# Syntax: create_monitor "Display Name" "URL" "type"
create_monitor "My Service" "https://myservice.example.com" "https"
create_monitor "My Internal API" "http://my-api.default.svc:8080" "http"
```

**Monitor Types**:

-   `https` - HTTPS check
-   `http` - HTTP check
-   `tcp` - TCP port check
-   `ping` - ICMP ping
-   `dns` - DNS lookup

### Re-running the Script

The script is idempotent and safe to re-run:

```bash
UPTIME_KUMA_USERNAME=admin \
UPTIME_KUMA_PASSWORD=password \
./scripts/setup-uptime-kuma.sh
```

### Manual API Usage

If you prefer manual API calls:

```bash
# Login
TOKEN=$(curl -k -s -X POST https://uptime.elate.me/api/login \
  -H "Content-Type: application/json" \
  -d '{"username":"admin","password":"yourpass"}' \
  | jq -r '.token')

# Create monitor
curl -k -X POST https://uptime.elate.me/api/monitor \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $TOKEN" \
  -d '{
    "type": "https",
    "name": "My Monitor",
    "url": "https://example.com",
    "interval": 60,
    "maxretries": 3
  }'

# List monitors
curl -k -s https://uptime.elate.me/api/monitor-list \
  -H "Authorization: Bearer $TOKEN"
```

---

## Kubernetes Job for Automated Setup

For fully automated setup, create a Kubernetes Job:

```yaml
apiVersion: batch/v1
kind: Job
metadata:
    name: uptime-kuma-setup
    namespace: uptime-kuma
spec:
    template:
        spec:
            restartPolicy: OnFailure
            containers:
                - name: setup
                  image: curlimages/curl:latest
                  env:
                      - name: UPTIME_KUMA_USERNAME
                        valueFrom:
                            secretKeyRef:
                                name: uptime-kuma-credentials
                                key: username
                      - name: UPTIME_KUMA_PASSWORD
                        valueFrom:
                            secretKeyRef:
                                name: uptime-kuma-credentials
                                key: password
                  command: ["/bin/sh"]
                  args:
                      - -c
                      - |
                          # Wait for Uptime Kuma to be ready
                          sleep 30

                          # Run setup script
                          /scripts/setup-uptime-kuma.sh
                  volumeMounts:
                      - name: scripts
                        mountPath: /scripts
            volumes:
                - name: scripts
                  configMap:
                      name: uptime-kuma-setup-script
                      defaultMode: 0755
```

---

## Infrastructure as Code

### Current Setup

All configurations are in Git:

-   **Grafana datasources**: `helm/grafana/templates/grafana-datasources.yaml`
-   **Uptime Kuma script**: `scripts/setup-uptime-kuma.sh`
-   **Service definitions**: Helm charts under `helm/`; `manifests/` is reserved for supporting cluster-wide resources

### Best Practices

1. **Version control**: All config changes should be committed to Git
2. **Secrets management**: Use Kubernetes Secrets or Sealed Secrets for credentials
3. **Documentation**: Update this file when adding new services
4. **Testing**: Test configuration changes in dev before applying to production

### Applying Changes

```bash
# Reconcile the monitoring releases
helm upgrade --install monitoring-baseline helm/monitoring-baseline -n monitoring
helm upgrade --install grafana helm/grafana -n monitoring
helm upgrade --install uptime-kuma helm/uptime-kuma -n uptime-kuma

# Update Grafana datasources
helm upgrade grafana helm/grafana -n monitoring
kubectl rollout restart deployment grafana -n monitoring

# Setup Uptime Kuma monitors
./scripts/setup-uptime-kuma.sh
```

---

## Troubleshooting

### Grafana Datasources Not Loading

**Check ConfigMap**:

```bash
kubectl get configmap grafana-datasources -n monitoring -o yaml
```

**Check mount**:

```bash
kubectl exec -n monitoring deployment/grafana -- \
  ls -la /etc/grafana/provisioning/datasources/
```

**Check logs**:

```bash
kubectl logs -n monitoring deployment/grafana | grep provisioning
```

### Uptime Kuma Script Fails

**Check connectivity**:

```bash
curl -k https://uptime.elate.me
```

**Check if setup is needed**:

```bash
curl -k -s https://uptime.elate.me/api/entry-page | jq
```

**Enable debug mode**:

```bash
bash -x ./scripts/setup-uptime-kuma.sh
```

---

## Next Steps

1. **Import Grafana Dashboards**: Use dashboard provisioning similar to datasources
2. **Configure Notifications**: Set up Uptime Kuma notification integrations
3. **Create Status Page**: Use Uptime Kuma's public status page feature
4. **Automate Backups**: Schedule backups of Grafana dashboards and Uptime Kuma data

---

**Last Updated**: January 2026
