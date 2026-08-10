#!/bin/bash
# Uptime Kuma API Setup Script
# This script configures Uptime Kuma monitors programmatically

set -e

UPTIME_KUMA_URL="${UPTIME_KUMA_URL:-https://uptime.elate.me}"
USERNAME="${UPTIME_KUMA_USERNAME:-}"
PASSWORD="${UPTIME_KUMA_PASSWORD:-}"

if [ -z "$USERNAME" ] || [ -z "$PASSWORD" ]; then
    echo "ERROR: Set UPTIME_KUMA_USERNAME and UPTIME_KUMA_PASSWORD before running this script."
    exit 1
fi

echo "========================================="
echo "Uptime Kuma Setup Script"
echo "========================================="
echo ""

# Check if Uptime Kuma is accessible
echo "Checking Uptime Kuma accessibility..."
if ! curl -k -s -o /dev/null -w "%{http_code}" "$UPTIME_KUMA_URL" | grep -q "302\|200"; then
    echo "ERROR: Cannot reach Uptime Kuma at $UPTIME_KUMA_URL"
    exit 1
fi
echo "✓ Uptime Kuma is accessible"
echo ""

# Check if setup is needed (first-time setup)
echo "Checking if Uptime Kuma needs initial setup..."
NEEDS_SETUP=$(curl -k -s "$UPTIME_KUMA_URL/api/entry-page" | grep -o '"needSetup":[^,}]*' | cut -d':' -f2)

if [ "$NEEDS_SETUP" = "true" ]; then
    echo "⚠️  First-time setup required!"
    echo ""
    echo "Please complete the initial setup manually at: $UPTIME_KUMA_URL"
    echo ""
    echo "After setup, run this script again with your credentials:"
    echo "  UPTIME_KUMA_USERNAME=admin UPTIME_KUMA_PASSWORD=yourpass $0"
    echo ""
    exit 0
fi

echo "✓ Uptime Kuma is already set up"
echo ""

# Login and get token
echo "Logging in to Uptime Kuma..."
TOKEN_RESPONSE=$(curl -k -s -X POST "$UPTIME_KUMA_URL/api/login" \
    -H "Content-Type: application/json" \
    -d "{\"username\":\"$USERNAME\",\"password\":\"$PASSWORD\"}")

if ! echo "$TOKEN_RESPONSE" | grep -q '"ok":true'; then
    echo "ERROR: Login failed. Check your credentials."
    echo "Response: $TOKEN_RESPONSE"
    exit 1
fi

TOKEN=$(echo "$TOKEN_RESPONSE" | grep -o '"token":"[^"]*"' | cut -d'"' -f4)
echo "✓ Login successful"
echo ""

# Function to create a monitor
create_monitor() {
    local name="$1"
    local url="$2"
    local type="${3:-https}"

    echo "Creating monitor: $name ($url)"

    MONITOR_DATA=$(cat <<EOF
{
    "type": "$type",
    "name": "$name",
    "url": "$url",
    "interval": 60,
    "retryInterval": 60,
    "maxretries": 3,
    "notificationIDList": {},
    "ignoreTls": true,
    "upsideDown": false,
    "maxredirects": 10,
    "accepted_statuscodes": ["200-299"],
    "dns_resolve_type": "A",
    "dns_resolve_server": "1.1.1.1",
    "proxyId": null,
    "method": "GET",
    "body": null,
    "headers": null,
    "authMethod": null,
    "active": true
}
EOF
)

    RESPONSE=$(curl -k -s -X POST "$UPTIME_KUMA_URL/api/monitor" \
        -H "Content-Type: application/json" \
        -H "Authorization: Bearer $TOKEN" \
        -d "$MONITOR_DATA")

    if echo "$RESPONSE" | grep -q '"ok":true'; then
        echo "  ✓ Monitor created successfully"
    else
        echo "  ⚠️  Failed to create monitor (may already exist)"
        echo "  Response: $RESPONSE"
    fi
}

# Create monitors for all services
echo "Creating monitors for homelab services..."
echo ""

create_monitor "Elate.me Public Site" "https://elate.me" "https"
create_monitor "Elate.biz Public Site" "https://elate.biz" "https"
create_monitor "Grafana" "https://grafana.elate.me" "https"
create_monitor "Longhorn UI" "https://longhorn.elate.me" "https"
create_monitor "Pi-hole Admin" "https://pihole.elate.me/admin" "https"
create_monitor "Traefik Dashboard" "https://traefik.elate.me" "https"
create_monitor "Dev Environment" "https://dev.elate.me" "https"
create_monitor "HomeLab Environment" "https://homelab.elate.me" "https"

# Internal services (HTTP only, no TLS)
echo ""
echo "Creating monitors for internal services..."
echo ""

create_monitor "Prometheus Server" "http://prometheus-server.monitoring.svc.cluster.local" "http"
create_monitor "Alertmanager" "http://prometheus-alertmanager.monitoring.svc.cluster.local:9093" "http"

echo ""
echo "========================================="
echo "Setup Complete!"
echo "========================================="
echo ""
echo "All monitors have been configured."
echo "Visit $UPTIME_KUMA_URL to view your monitoring dashboard."
echo ""
