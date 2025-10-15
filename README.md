# Bitcoin Testnet Node with Monitoring

This project provides a one-click deployment solution for running a Bitcoin testnet node on a local Kubernetes cluster with comprehensive monitoring using Prometheus and Grafana. Downloaded chart bitcoin-stack from https://artifacthub.io/packages/helm/k8s-charts/bitcoin-stack
which is compatible with blockstream/bitcoin docker image. 
Customized the chart with some improvements like Horizontal Pod Autoscaling or Headless services.
Right now autoscaling is 'disabled' minReplicas = maxReplicas = 1, in order to not consume local resources, but has been tested 1 to 3 replicas. To 'activate' autoscaling change maxReplicas in bitcoin-values.yaml.

Tested on local laptop and Amazon EC2 instance, for any questions do not hesitate in contacting me.
## Architecture Overview

- **Local Kubernetes Cluster**: Uses `kind` (Kubernetes in Docker) for local development
- **Bitcoin Node**: Runs `blockstream/bitcoind:27.0` with testnet configuration using kriegalex/k8s-charts/bitcoin-stack Helm chart
- **Monitoring Stack**: Prometheus for metrics collection, Grafana for visualization using prometheus-community/kube-prometheus-stack
- **Bitcoin Exporter**: Custom Python-based Prometheus exporter that collects metrics via HTTP RPC calls

## Prerequisites

Before running the deployment, ensure you have the following tools installed:

- **Docker**: For running containers
- **kind**: For creating local Kubernetes clusters
  ```bash
  go install sigs.k8s.io/kind@v0.20.0
  ```
- **kubectl**: For managing Kubernetes resources
  ```bash
  # macOS
  brew install kubectl
  
  # Linux
  curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
  chmod +x kubectl
  sudo mv kubectl /usr/local/bin/
  ```
- **Helm**: For deploying Helm charts
  ```bash
  # macOS
  brew install helm
  
  # Linux
  curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
  ```

## Quick Start

```bash
# Clone the repository
git clone <repository-url>
cd bitcoin-testnet-node

# Make the deployment script executable
chmod +x deploy-helm.sh

# Run one-click deployment
./deploy-helm.sh
```

## Project Structure

```
├── deploy-helm.sh                         # One-click deployment script
├── cleanup.sh                             # Cleanup script to remove cluster
├── bitcoin-values.yaml                    # Helm values for Bitcoin stack
├── bitcoin_exporter.py                    # Custom Bitcoin metrics exporter
├── Dockerfile.bitcoin-exporter            # Docker image for Bitcoin exporter
├── config.yaml                            # Configuration file for frequently used values
├── cluster-config.yaml                    # Kind cluster configuration
├── charts/                                # Local Helm charts
│   └── bitcoin-stack-custom/              # Custom Bitcoin chart with headless service and HPA
├── k8s/                                   # Kubernetes manifests
│   └── exporter/                          # Bitcoin metrics exporter
│       ├── custom-bitcoin-exporter-deployment.yaml
│       └── custom-bitcoin-exporter-service.yaml
├── grafana/                               # Grafana dashboards and configs
│   └── dashboards/
│       └── bitcoin-dashboard.json         # Bitcoin monitoring dashboard
└── README.md                              # This file
```

## Configuration Details

### Bitcoin Node Configuration
- **Network**: Testnet (reduced resource requirements)
- **Image**: `blockstream/bitcoind:27.0`
- **Helm Chart**: Custom local chart (`charts/bitcoin-stack-custom`) with headless service support
- **RPC**: Enabled for metrics collection with auto-generated credentials
- **Storage**: 700GB persistent volume (configurable in bitcoin-values.yaml)
- **Resources**: Configurable CPU and memory limits
- **Autoscaling**: Horizontal Pod Autoscaler (HPA) enabled by default

#### Horizontal Pod Autoscaler (HPA)
The Bitcoin StatefulSet includes automatic scaling based on CPU and memory utilization via the custom Helm chart:

```yaml
# -- Autoscaling configuration
autoscaling:
  enabled: true
  minReplicas: 1
  maxReplicas: 1
  targetCPUUtilizationPercentage: 70
  targetMemoryUtilizationPercentage: 80
  # Scaling behavior configuration
  scaleDownStabilizationWindowSeconds: 300  # 5 minutes
  scaleDownPercent: 50
  scaleDownPeriodSeconds: 60
  scaleUpStabilizationWindowSeconds: 60     # 1 minute
  scaleUpPercent: 100
  scaleUpPeriodSeconds: 60
```

**HPA Features:**
- **CPU Target**: Scales up when CPU usage exceeds 70%
- **Memory Target**: Scales up when memory usage exceeds 80%
- **Scale Range**: 1 to 3 replicas
- **Conservative Scale-down**: 5-minute stabilization window
- **Aggressive Scale-up**: 1-minute stabilization window

#### Multi-Pod Support
- **Headless Service**: Each Bitcoin pod is individually addressable
- **Pod Discovery**: Exporter automatically discovers all Bitcoin pods
- **Individual Metrics**: Each pod's metrics are labeled with pod name
- **No Port Conflicts**: Each pod has unique DNS name

**Note**: Each replica will have its own persistent volume and will sync the blockchain independently. This is useful for:
- High availability setups
- Load testing scenarios
- Development environments with multiple nodes

### Monitoring Configuration
- **Prometheus**: Scrapes metrics every 30 seconds
- **Grafana**: Pre-configured dashboards for Bitcoin metrics
- **Helm Chart**: `prometheus-community/kube-prometheus-stack`
- **Retention**: Configurable Prometheus data retention
- **Storage**: Configurable storage for Prometheus and Grafana

### Bitcoin Exporter
- **Type**: Custom Python-based exporter
- **Image**: Built from `Dockerfile.bitcoin-exporter`
- **Metrics**: Block height, peer count, connections, difficulty, verification progress
- **Port**: 8000
- **Authentication**: Uses Kubernetes secrets for RPC credentials


## Accessing the Services

After deployment, the services will be accessible via port forwarding:

- **Grafana**: http://localhost:30000 (admin/admin)
- **Prometheus**: http://localhost:30001
- **Bitcoin RPC**: localhost:18332 (bitcoin/[auto-generated-password])

### Port Forwarding (Automatic Setup)

The deployment script automatically sets up port forwarding:

```bash
# Grafana (automatically configured)
kubectl port-forward -n monitoring svc/prometheus-grafana 30000:80

# Prometheus (automatically configured)
kubectl port-forward -n monitoring svc/prometheus-kube-prometheus-prometheus 30001:9090

# Bitcoin RPC (automatically configured)
kubectl port-forward -n bitcoin svc/bitcoin-stack 18332:18332
```

### Dashboard Access
The dashboard is automatically imported during deployment:

1. Access Grafana at http://localhost:30000
2. Login with admin/admin
3. The "Bitcoin Testnet Node Monitoring" dashboard is automatically available
   ```

## Cleanup

To remove the entire deployment:

```bash
./cleanup.sh
```

Or manually:

```bash
kind delete cluster --name bitcoin-cluster
```