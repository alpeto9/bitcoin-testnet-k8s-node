#!/bin/bash

# Bitcoin Testnet Node with Monitoring - Simplified One Click Deployment
# This script uses existing Helm charts for a more production-ready setup

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print colored output
print_status() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Configuration file path
CONFIG_FILE="config.yaml"

# Function to load configuration
load_config() {
    if [[ ! -f "$CONFIG_FILE" ]]; then
        print_error "Configuration file not found: $CONFIG_FILE"
        exit 1
    fi
    
    print_status "Loading configuration from $CONFIG_FILE..."
    
    # Load only frequently used configuration values (4+ times)
    if command -v yq &> /dev/null; then
        CLUSTER_NAME=$(yq eval '.cluster.name' "$CONFIG_FILE")
        CLUSTER_CONFIG_FILE=$(yq eval '.cluster.config_file' "$CONFIG_FILE")
        BITCOIN_NAMESPACE=$(yq eval '.namespaces.bitcoin' "$CONFIG_FILE")
        MONITORING_NAMESPACE=$(yq eval '.namespaces.monitoring' "$CONFIG_FILE")
        BITCOIN_RELEASE_NAME=$(yq eval '.bitcoin.release_name' "$CONFIG_FILE")
        GRAFANA_ADMIN_PASSWORD=$(yq eval '.monitoring.grafana.admin_password' "$CONFIG_FILE")
    else
        print_warning "yq not found, using hardcoded values. Install yq for configuration support."
        CLUSTER_NAME="bitcoin-cluster"
        CLUSTER_CONFIG_FILE="cluster-config.yaml"
        BITCOIN_NAMESPACE="bitcoin"
        MONITORING_NAMESPACE="monitoring"
        BITCOIN_RELEASE_NAME="bitcoin-stack"
        GRAFANA_ADMIN_PASSWORD="admin"
    fi
    
    print_success "Configuration loaded successfully"
}

# Function to find working kubectl
find_working_kubectl() {
    # List of possible kubectl locations
    KUBECTL_PATHS=(
        "/usr/local/bin/kubectl"
        "/usr/bin/kubectl"
        "/opt/homebrew/bin/kubectl"
        "$(which kubectl)"
        "$HOME/go/bin/kubectl"
    )
    
    for path in "${KUBECTL_PATHS[@]}"; do
        if [[ -n "$path" && -x "$path" ]]; then
            if "$path" version --client &> /dev/null; then
                echo "$path"
                return 0
            fi
        fi
    done
    
    return 1
}

# Set kubectl command globally
print_status "Finding working kubectl installation..."
export kubectl_cmd=$(find_working_kubectl)
if [[ -z "$kubectl_cmd" ]]; then
    print_error "No working kubectl found!"
    exit 1
fi
print_success "Found working kubectl at: $kubectl_cmd"

# Check prerequisites
check_prerequisites() {
    print_status "Checking prerequisites..."
    
    # Check if Docker is running
    if ! docker info &> /dev/null; then
        print_error "Docker is not running. Please start Docker and try again."
        exit 1
    fi
    
    # Check if kind is installed
    if ! command -v kind &> /dev/null; then
        print_error "kind is not installed. Please install kind and try again."
        exit 1
    fi
    
    # Check if helm is installed
    if ! command -v helm &> /dev/null; then
        print_error "helm is not installed. Please install helm and try again."
        exit 1
    fi
    
    print_success "All prerequisites met"
}

# Create Kubernetes cluster
create_k8s_cluster() {
    print_status "Creating Kubernetes cluster with kind..."
    
    # Check if cluster already exists
    if kind get clusters | grep -q "$CLUSTER_NAME"; then
        print_warning "Cluster '$CLUSTER_NAME' already exists. Deleting it..."
        kind delete cluster --name "$CLUSTER_NAME"
    fi
    
    # Create new cluster using cluster config file
    if [[ ! -f "$CLUSTER_CONFIG_FILE" ]]; then
        print_error "Cluster config file not found: $CLUSTER_CONFIG_FILE"
        exit 1
    fi
    
    kind create cluster --name "$CLUSTER_NAME" --image kindest/node:v1.28.0 --config "$CLUSTER_CONFIG_FILE"
    
    print_success "Kubernetes cluster created successfully"
}

# Setup Helm repositories
setup_helm_repos() {
    print_status "Setting up Helm repositories..."

    # Add Bitcoin Stack Helm chart repository
    helm repo add k8s-charts https://kriegalex.github.io/k8s-charts/ || true

    # Add Prometheus community Helm chart
    helm repo add prometheus-community https://prometheus-community.github.io/helm-charts

    # Update repositories
    helm repo update

    print_success "Helm repositories configured"
}

# Create namespaces
create_namespaces() {
    print_status "Creating namespaces..."
    
    $kubectl_cmd create namespace "$BITCOIN_NAMESPACE" --dry-run=client -o yaml | $kubectl_cmd apply -f -
    $kubectl_cmd create namespace "$MONITORING_NAMESPACE" --dry-run=client -o yaml | $kubectl_cmd apply -f -
    
    print_success "Namespaces created"
}

# Install metrics server for HPA
install_metrics_server() {
    print_status "Installing metrics server for HPA..."
    
    # Check if metrics server is already installed
    if $kubectl_cmd get deployment metrics-server -n kube-system &> /dev/null; then
        print_status "Metrics server already installed, checking status..."
        $kubectl_cmd get pods -n kube-system | grep metrics-server
        return 0
    fi
    
    # Install metrics server with Kind-specific configuration
    print_status "Installing metrics server with Kind-specific configuration..."
    $kubectl_cmd apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml
    
    # Patch the deployment to add Kind-specific arguments
    $kubectl_cmd patch deployment metrics-server -n kube-system --type='json' -p='[{"op": "add", "path": "/spec/template/spec/containers/0/args/-", "value": "--kubelet-insecure-tls"}]'
    
    # Wait for metrics server to be ready
    print_status "Waiting for metrics server to be ready..."
    $kubectl_cmd rollout status deployment/metrics-server -n kube-system
    
    print_success "Metrics server installed successfully"
}


# Prepull Bitcoin image
prepull_bitcoin_image() {
    print_status "Pre-pulling Bitcoin image to kind cluster..."
    
    # Pull the Bitcoin image
    docker pull blockstream/bitcoind:27.0
    
    # Load the image into kind cluster
    kind load docker-image blockstream/bitcoind:27.0 --name "$CLUSTER_NAME"
    
    print_success "Bitcoin image prepared"
}

# Deploy Bitcoin node using Helm
deploy_bitcoin_helm() {
    print_status "Deploying Bitcoin testnet node using Helm..."

    # Install Bitcoin node with testnet configuration using bitcoin-stack chart
    print_status "Installing Bitcoin node with Helm..."
    helm upgrade --install "$BITCOIN_RELEASE_NAME" ./charts/bitcoin-stack-custom \
        --namespace "$BITCOIN_NAMESPACE" \
        --values bitcoin-values.yaml

    print_success "Bitcoin node deployed via Helm"
}



# Build and deploy custom Bitcoin exporter
build_and_deploy_exporter() {
    print_status "Building Bitcoin exporter Docker image..."
    
    # Build the Bitcoin exporter image
    docker build -f Dockerfile.bitcoin-exporter -t bitcoin-exporter:latest .
    
    # Load the image into kind cluster
    print_status "Loading Bitcoin exporter image into kind cluster..."
    kind load docker-image bitcoin-exporter:latest --name "$CLUSTER_NAME"
    
    print_status "Deploying Bitcoin metrics exporter..."
    $kubectl_cmd apply -f k8s/exporter/custom-bitcoin-exporter-deployment.yaml
    $kubectl_cmd apply -f k8s/exporter/custom-bitcoin-exporter-service.yaml
    
    print_success "Bitcoin exporter deployed"
}

# Deploy monitoring stack (Prometheus + Grafana)
deploy_monitoring_helm() {
    print_status "Deploying monitoring stack using Helm..."
    
    # Install Prometheus and Grafana with kube-prometheus-stack
    print_status "Installing Prometheus and Grafana with Helm..."
    helm upgrade --install prometheus prometheus-community/kube-prometheus-stack \
        --namespace "$MONITORING_NAMESPACE" \
        --set prometheus.prometheusSpec.additionalScrapeConfigs[0].job_name=bitcoin-exporter \
        --set prometheus.prometheusSpec.additionalScrapeConfigs[0].static_configs[0].targets[0]=custom-bitcoin-exporter.bitcoin.svc.cluster.local:8000 \
        --set grafana.adminPassword="$GRAFANA_ADMIN_PASSWORD" \
        --set grafana.service.type=NodePort \
        --set grafana.service.nodePort=30000 \
        --set prometheus.service.type=NodePort \
        --set prometheus.service.nodePort=30001
    
    print_success "Monitoring stack deployed via Helm"
}

# Import Bitcoin dashboard to Grafana
import_grafana_dashboard() {
    print_status "Importing Bitcoin dashboard to Grafana..."
    
    # Wait for Grafana to be ready
    print_status "Waiting for Grafana to be ready..."
    $kubectl_cmd wait --for=condition=available --timeout=300s deployment/prometheus-grafana -n "$MONITORING_NAMESPACE" || {
        print_warning "Grafana deployment timeout, checking status..."
        $kubectl_cmd get pods -n "$MONITORING_NAMESPACE"
    }
    
    # Find Grafana pod
    GRAFANA_POD=$($kubectl_cmd get pods -n "$MONITORING_NAMESPACE" -l app.kubernetes.io/name=grafana -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
    
    if [[ -n "$GRAFANA_POD" ]]; then
        print_status "Found Grafana pod: $GRAFANA_POD"
        
        # Use the correct Bitcoin dashboard JSON file
        print_status "Using Bitcoin dashboard from grafana/dashboards/bitcoin-dashboard.json..."
        
        # Check if the dashboard file exists
        if [[ ! -f "grafana/dashboards/bitcoin-dashboard.json" ]]; then
            print_error "Bitcoin dashboard file not found: grafana/dashboards/bitcoin-dashboard.json"
            return 1
        fi
        
        # Copy dashboard to Grafana pod and import
        print_status "Copying dashboard to Grafana pod..."
        $kubectl_cmd cp grafana/dashboards/bitcoin-dashboard.json "$MONITORING_NAMESPACE/$GRAFANA_POD:/tmp/bitcoin-dashboard.json"
        
        # Import dashboard via Grafana API
        print_status "Importing dashboard via Grafana API..."
        $kubectl_cmd exec -n "$MONITORING_NAMESPACE" "$GRAFANA_POD" -- curl -X POST \
            -H "Content-Type: application/json" \
            -d @/tmp/bitcoin-dashboard.json \
            "http://admin:$GRAFANA_ADMIN_PASSWORD@localhost:3000/api/dashboards/db"
        
        print_success "Bitcoin dashboard imported successfully"
    else
        print_warning "Could not find Grafana pod, dashboard will need to be imported manually"
    fi
}

# Setup port forwarding for local access
setup_port_forwarding() {
    print_status "Setting up port forwarding..."
    
    # Kill any existing port forwards
    pkill -f "kubectl port-forward" 2>/dev/null || true
    
    # Setup port forwarding for Grafana
    print_status "Setting up port forwarding for Grafana (port 3000)..."
    $kubectl_cmd port-forward -n "$MONITORING_NAMESPACE" svc/prometheus-grafana 3000:80 &
    
    # Setup port forwarding for Prometheus
    print_status "Setting up port forwarding for Prometheus (port 9090)..."
    $kubectl_cmd port-forward -n "$MONITORING_NAMESPACE" svc/prometheus-kube-prometheus-prometheus 9090:9090 &
    
    # Setup port forwarding for Bitcoin RPC
    print_status "Setting up port forwarding for Bitcoin RPC (port 18332)..."
    $kubectl_cmd port-forward -n "$BITCOIN_NAMESPACE" svc/"$BITCOIN_RELEASE_NAME" 18332:18332 &
    
    print_success "Port forwarding setup complete"
}

# Display status and access information
show_status() {
    print_status "Access URLs:"
    print_status "  Grafana: http://localhost:3000 (admin/$GRAFANA_ADMIN_PASSWORD)"
    print_status "  Prometheus: http://localhost:9090"
    print_status "  Bitcoin RPC: localhost:18332 (bitcoin/bitcoin) - testnet"
    print_status ""
    print_status "Deployment Status:"
    print_status ""
    print_status "Bitcoin Node:"
    $kubectl_cmd get pods -n "$BITCOIN_NAMESPACE"
    print_status ""
    print_status "Monitoring Stack:"
    $kubectl_cmd get pods -n "$MONITORING_NAMESPACE"
    print_status ""
    print_status "Services:"
    $kubectl_cmd get svc -n "$BITCOIN_NAMESPACE"
    $kubectl_cmd get svc -n "$MONITORING_NAMESPACE"
    print_status ""
    print_status ""
    print_status "Bitcoind Service Details:"
    $kubectl_cmd get svc -n "$BITCOIN_NAMESPACE" | grep -i bitcoin || print_warning "No Bitcoin services found"
    print_status ""
    print_status "Horizontal Pod Autoscaler:"
    $kubectl_cmd get hpa -n "$BITCOIN_NAMESPACE" || print_warning "No HPA found"
}

# Main deployment function
main() {
    print_status "Starting Bitcoin Testnet Node with Monitoring deployment (Helm-based)..."
    echo ""
    
    load_config
    check_prerequisites
    create_k8s_cluster
    setup_helm_repos
    create_namespaces
    install_metrics_server
    prepull_bitcoin_image
    deploy_bitcoin_helm
    
    print_status "Bitcoin node deployed, now deploying monitoring stack..."
    build_and_deploy_exporter
    deploy_monitoring_helm
    import_grafana_dashboard
    setup_port_forwarding
    show_status
    
    print_success "Deployment completed successfully!"
    echo ""
    print_status "Next steps:"
    print_status "1. Wait a few minutes for Bitcoin node to sync with testnet"
    print_status "2. Access Grafana at http://localhost:30000 (admin/admin)"
    print_status "3. Bitcoin dashboard has been automatically imported!"
    print_status "4. Monitor your Bitcoin node metrics!"
    echo ""
    print_status "Useful commands:"
    print_status "  Check Bitcoin node logs: kubectl logs -n bitcoin bitcoin-stack-0 -c bitcoin-stack -f"
    print_status "  Check exporter logs: kubectl logs -n bitcoin deployment/custom-bitcoin-exporter -f"
    print_status "  Check all pods: kubectl get pods --all-namespaces"
    print_status "  Check HPA status: kubectl get hpa -n bitcoin -w"
    print_status "  Check HPA details: kubectl describe hpa bitcoin-stack-hpa -n bitcoin"
    print_status "  Clean up: ./cleanup.sh"
    echo ""
    print_warning "Note: Bitcoin node sync may take some time depending on your internet connection"
}

# Run main function
main "$@"