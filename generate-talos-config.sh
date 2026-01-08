#!/bin/bash

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Default values
CLUSTER_NAME="homelab"
CONTROL_PLANE_ENDPOINT="https://192.168.1.41:6443"
GATEWAY="192.168.1.1"
NAMESERVER="192.168.1.1"
INTERFACE="enp2s0"
SUBNET_MASK="24"

# Function to display help
show_help() {
    cat << EOF
Usage: $(basename "$0") [OPTIONS]

Generate Talos node configuration with custom patches.

Required Options:
    -t, --type TYPE             Node type: controlplane or worker
    -i, --ip IP                 Node IP address (e.g., 192.168.1.42)

Optional Options:
    -n, --name NAME             Cluster name (default: $CLUSTER_NAME)
    -e, --endpoint ENDPOINT     Control plane endpoint (default: $CONTROL_PLANE_ENDPOINT)
    -g, --gateway GATEWAY       Network gateway (default: $GATEWAY)
    -d, --dns DNS               DNS nameserver (default: $NAMESERVER)
    -I, --interface IFACE       Network interface (default: $INTERFACE)
    -s, --subnet MASK           Subnet mask (default: $SUBNET_MASK)
    -h, --help                  Show this help message

Examples:
    # Generate controlplane config
    $(basename "$0") -t controlplane -i 192.168.1.41

    # Generate worker config with custom gateway
    $(basename "$0") -t worker -i 192.168.1.42 -g 192.168.1.254

EOF
}

# Parse command line arguments
NODE_TYPE=""
NODE_IP=""

while [[ $# -gt 0 ]]; do
    case $1 in
        -t|--type)
            NODE_TYPE="$2"
            shift 2
            ;;
        -i|--ip)
            NODE_IP="$2"
            shift 2
            ;;
        -n|--name)
            CLUSTER_NAME="$2"
            shift 2
            ;;
        -e|--endpoint)
            CONTROL_PLANE_ENDPOINT="$2"
            shift 2
            ;;
        -g|--gateway)
            GATEWAY="$2"
            shift 2
            ;;
        -d|--dns)
            NAMESERVER="$2"
            shift 2
            ;;
        -I|--interface)
            INTERFACE="$2"
            shift 2
            ;;
        -s|--subnet)
            SUBNET_MASK="$2"
            shift 2
            ;;
        -h|--help)
            show_help
            exit 0
            ;;
        *)
            echo -e "${RED}Error: Unknown option $1${NC}"
            show_help
            exit 1
            ;;
    esac
done

# Validate required arguments
if [[ -z "$NODE_TYPE" ]]; then
    echo -e "${RED}Error: Node type is required${NC}"
    show_help
    exit 1
fi

if [[ -z "$NODE_IP" ]]; then
    echo -e "${RED}Error: Node IP is required${NC}"
    show_help
    exit 1
fi

# Validate node type
if [[ "$NODE_TYPE" != "controlplane" && "$NODE_TYPE" != "worker" ]]; then
    echo -e "${RED}Error: Node type must be 'controlplane' or 'worker'${NC}"
    exit 1
fi

# Check if talosctl is installed
if ! command -v talosctl &> /dev/null; then
    echo -e "${RED}Error: talosctl is not installed${NC}"
    echo "Please install talosctl: https://www.talos.dev/latest/introduction/getting-started/"
    exit 1
fi

echo -e "${GREEN}Generating Talos configuration...${NC}"
echo "  Cluster: $CLUSTER_NAME"
echo "  Type: $NODE_TYPE"
echo "  IP: $NODE_IP/$SUBNET_MASK"
echo "  Gateway: $GATEWAY"
echo "  DNS: $NAMESERVER"
echo "  Control Plane: $CONTROL_PLANE_ENDPOINT"
echo ""

# Create temporary patch file
PATCH_FILE=$(mktemp)
trap "rm -f $PATCH_FILE" EXIT

cat > "$PATCH_FILE" << EOF
machine:
  kernel:
    modules:
      - name: nbd
      - name: iscsi_tcp
      - name: iscsi_generic
      - name: configfs
  network:
    interfaces:
      - interface: $INTERFACE
        dhcp: false
        addresses:
          - $NODE_IP/$SUBNET_MASK
        routes:
          - network: 0.0.0.0/0
            gateway: $GATEWAY
    nameservers:
      - $NAMESERVER
cluster:
  controlPlane:
    endpoint: $CONTROL_PLANE_ENDPOINT
  apiServer:
    certSANs:
      - $NODE_IP
EOF

# Generate the configuration
if talosctl gen config "$CLUSTER_NAME" "$CONTROL_PLANE_ENDPOINT" \
    --config-patch @"$PATCH_FILE" \
    --output-types "$NODE_TYPE" \
    --output "$NODE_TYPE.yaml" \
    --force; then

    echo -e "${GREEN}Success!${NC}"
    echo "Configuration generated: $NODE_TYPE.yaml"
    echo ""
    echo -e "${YELLOW}Next steps:${NC}"
    echo "1. Review the generated $NODE_TYPE.yaml file"
    echo "2. Apply to node: talosctl apply-config --insecure --nodes $NODE_IP --file $NODE_TYPE.yaml"
    echo "3. Generate talosconfig: talosctl config merge ./talosconfig"
else
    echo -e "${RED}Failed to generate configuration${NC}"
    exit 1
fi
