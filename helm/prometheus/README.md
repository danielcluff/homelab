# Prometheus

Deploy the pinned upstream chart after the monitoring namespace baseline:

```bash
helm upgrade --install monitoring-baseline helm/monitoring-baseline \
  --namespace monitoring --take-ownership

helm upgrade prometheus prometheus-community/prometheus \
  --version 28.2.1 \
  --namespace monitoring \
  --values helm/prometheus/values.yaml
```

The namespace is deliberately privileged because node-exporter requires host
PID, host networking and read-only host filesystem mounts.

