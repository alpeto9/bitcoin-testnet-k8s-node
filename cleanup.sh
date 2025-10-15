#!/bin/bash

# Cleanup script for Bitcoin Testnet Node with Monitoring
# This script removes the local Kubernetes cluster and all resources

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

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

# Check if cluster exists
if ! kind get clusters | grep -q "bitcoin-cluster"; then
    print_warning "Cluster 'bitcoin-cluster' does not exist. Nothing to clean up."
    exit 0
fi

print_status "Cleaning up Bitcoin Testnet Node deployment..."

# Delete the cluster
print_status "Deleting Kubernetes cluster..."
kind delete cluster --name bitcoin-cluster

print_success "Cleanup completed successfully!"
print_status "All resources have been removed."
