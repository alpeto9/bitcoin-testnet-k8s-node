# Configuration Guide

This project uses a simplified configuration approach with two files:
- `config.yaml` - Only for frequently used values (4+ times)
- `cluster-config.yaml` - Kind cluster configuration

## Configuration Files

### `config.yaml` - Frequently Used Values Only
Contains only values that are used 4 or more times in the script:
- Cluster name
- Namespace names
- Bitcoin release name
- Grafana admin password

### `cluster-config.yaml` - Kind Cluster Configuration
Contains the complete Kind cluster configuration including:
- Node configuration
- Port mappings
- Kubeadm patches

## Benefits

1. **Simplified**: Only configurable values that are used frequently
2. **Clean**: Hardcoded values for infrequently used settings
3. **Maintainable**: Less configuration to manage
4. **Flexible**: Easy to customize the important settings

## Usage

1. **Default Configuration**: The script will use the default `config.yaml` file
2. **Custom Configuration**: Modify `config.yaml` to change frequently used settings
3. **Cluster Configuration**: Modify `cluster-config.yaml` to change Kind cluster settings
4. **Optional yq**: Works with or without `yq` (with fallback values)

## Key Configuration Sections

### Cluster Settings
```yaml
cluster:
  name: "bitcoin-cluster"
  config_file: "cluster-config.yaml"
```

### Namespaces (used 4+ times)
```yaml
namespaces:
  bitcoin: "bitcoin"
  monitoring: "monitoring"
```

### Bitcoin Release Name (used 4+ times)
```yaml
bitcoin:
  release_name: "bitcoin-stack"
```

### Grafana Admin Password (used 4+ times)
```yaml
monitoring:
  grafana:
    admin_password: "admin"
```

## Customization Examples

### Change Cluster Name
```yaml
cluster:
  name: "my-bitcoin-cluster"
```

### Change Namespaces
```yaml
namespaces:
  bitcoin: "my-bitcoin-ns"
  monitoring: "my-monitoring-ns"
```

### Change Grafana Password
```yaml
monitoring:
  grafana:
    admin_password: "my-secure-password"
```

### Change Bitcoin Release Name
```yaml
bitcoin:
  release_name: "my-bitcoin-release"
```

## Hardcoded Values

The following values are hardcoded in the script (used less than 4 times):
- Bitcoin image: `blockstream/bitcoind:27.0`
- Exporter image: `bitcoin-exporter:latest`
- Helm chart repositories and names
- Port numbers (3000, 9090, 18332)
- File paths (Dockerfile, YAML files)
- Service types and node ports

## Requirements

- **Optional**: `yq` for better YAML parsing (fallback values provided if not available)
- **Required**: All referenced files must exist (dashboard, values files, etc.)

## File Structure

```
├── config.yaml                    # Simplified configuration (frequently used values only)
├── cluster-config.yaml            # Kind cluster configuration
├── deploy-helm.sh                 # Updated deployment script
├── bitcoin-values.yaml            # Bitcoin Helm values
├── grafana/dashboards/
│   └── bitcoin-dashboard.json     # Grafana dashboard
└── k8s/exporter/                  # Exporter manifests
```
