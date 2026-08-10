# Quick Start: Programmatic Monitoring Setup

## ✅ What's Already Configured

### Grafana Datasources (Automatic)

Grafana datasources are **already configured** and will load automatically:

✅ **Prometheus** - Primary metrics source (default)
✅ **Alertmanager** - Alert management

**Verify**: Sign in with the current Grafana administrator account and visit https://grafana.elate.me/datasources. Grafana credentials are not stored in this repository.

The datasources are provisioned via ConfigMap and will persist across pod restarts.

---

## 🔧 Setup Uptime Kuma Monitors

Uptime Kuma monitors need to be configured after initial setup.

### Step 1: Complete Initial Setup

Visit https://uptime.elate.me and create your admin account.

### Step 2: Run Setup Script

```bash
cd /Users/daniel/dev/homelab

# Set your credentials
export UPTIME_KUMA_USERNAME=daniel
read -s "UPTIME_KUMA_PASSWORD?Uptime Kuma password: "
export UPTIME_KUMA_PASSWORD

# Run the script
./scripts/setup-uptime-kuma.sh
```

### What Gets Created

The script will create monitors for:

-   All your `*.elate.me` services (Heimdall, Grafana, Longhorn, etc.)
-   Internal services (Prometheus, Alertmanager)

---

## 📊 Adding More to Grafana

### Add More Datasources

Edit `helm/grafana/templates/grafana-datasources.yaml`:

```yaml
datasources:
    - name: My New Source
      type: prometheus
      url: http://my-service:9090
```

Apply changes:

```bash
helm upgrade grafana helm/grafana -n monitoring
kubectl rollout restart deployment grafana -n monitoring
```

### Import Dashboards

Grafana dashboards can also be provisioned. Add their ConfigMap and mounts to
the `helm/grafana/` chart so the release retains ownership:

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
    name: grafana-dashboards
    namespace: monitoring
data:
    dashboard-provider.yaml: |
        apiVersion: 1
        providers:
          - name: 'default'
            folder: ''
            type: file
            options:
              path: /var/lib/grafana/dashboards
```

Then mount dashboard JSON files similarly.

---

## 🔔 Adding More to Uptime Kuma

### Add Custom Monitors

Edit `scripts/setup-uptime-kuma.sh` and add:

```bash
# Add your custom monitors
create_monitor "My Website" "https://example.com" "https"
create_monitor "My API" "http://api.internal:8080/health" "http"
create_monitor "Database Port" "tcp://db.internal:5432" "tcp"
```

Re-run the script to apply changes.

---

## 📁 File Locations

```
homelab/
├── helm/
│   ├── grafana/                    # Grafana workload, ingress, and datasources
│   ├── monitoring-baseline/        # Monitoring namespace baseline
│   └── uptime-kuma/                # Uptime Kuma workload and ingress
├── scripts/
│   └── setup-uptime-kuma.sh        # Uptime Kuma setup script
└── MONITORING_SETUP.md             # Detailed documentation
```

---

## 🔍 Verification

### Check Grafana Datasources

```bash
# Via kubectl
kubectl exec -n monitoring deployment/grafana -- \
  cat /etc/grafana/provisioning/datasources/datasources.yaml

# Via UI
# Visit https://grafana.elate.me → Configuration → Data sources
```

### Check Uptime Kuma Monitors

```bash
# Visit https://uptime.elate.me
# All monitors should be listed on the dashboard
```

---

## 🚀 Next Steps

1. **Grafana**: Import pre-built dashboards from https://grafana.com/grafana/dashboards/

    - Kubernetes cluster monitoring: Dashboard ID 315
    - Node exporter: Dashboard ID 1860

2. **Uptime Kuma**: Configure notifications (Slack, Discord, email, etc.)

3. **Create Status Page**: Uptime Kuma can create public status pages

---

**Need Help?** See `MONITORING_SETUP.md` for detailed documentation.
