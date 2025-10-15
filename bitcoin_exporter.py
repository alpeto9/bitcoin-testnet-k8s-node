#!/usr/bin/env python3

import http.server
import socketserver
import json
import time
import os
import signal
import sys
import urllib.request
import urllib.parse
import base64
import socket
import threading
from concurrent.futures import ThreadPoolExecutor, as_completed

def make_bitcoin_rpc_call(method, params=None, target_host=None):
    """Make an HTTP request to Bitcoin RPC API"""
    try:
        # Get connection details from environment
        host = target_host or os.getenv("BITCOIN_HOST", "bitcoin-stack.bitcoin.svc.cluster.local")
        port = os.getenv("BITCOIN_PORT", "18332")
        user = os.getenv("BITCOIN_USER", "bitcoin")
        password = os.getenv("BITCOIN_PASSWORD", "bitcoin")
        
        # Create RPC URL
        url = f"http://{host}:{port}"
        
        # Create RPC request
        rpc_request = {
            "jsonrpc": "1.0",
            "id": "exporter",
            "method": method,
            "params": params or []
        }
        
        # Encode request data
        data = json.dumps(rpc_request).encode('utf-8')
        
        # Create request with basic auth
        request = urllib.request.Request(url, data=data)
        request.add_header('Content-Type', 'application/json')
        
        # Add basic authentication
        credentials = f"{user}:{password}"
        encoded_credentials = base64.b64encode(credentials.encode('utf-8')).decode('utf-8')
        request.add_header('Authorization', f'Basic {encoded_credentials}')
        
        # Make the request
        with urllib.request.urlopen(request, timeout=10) as response:
            result = json.loads(response.read().decode('utf-8'))
            return result.get('result', None)
            
    except Exception as e:
        # RPC call failed - return None for graceful handling
        return None

def discover_bitcoin_pods():
    """Discover all Bitcoin pods using DNS resolution for headless service"""
    pods = []
    
    # Get service details from environment variables
    service_name = os.getenv("BITCOIN_SERVICE_NAME", "bitcoin-stack")
    namespace = os.getenv("BITCOIN_NAMESPACE", "bitcoin")
    
    # For headless service, we need to resolve individual pod hostnames
    # Format: pod-name.service-name.namespace.svc.cluster.local
    base_host = f"{service_name}.{namespace}.svc.cluster.local"
    
    # Try to discover pods by attempting DNS resolution
    # StatefulSet pods follow the pattern: service-name-0, service-name-1, etc.
    for i in range(10):  # Try up to 10 pods
        pod_host = f"{service_name}-{i}.{base_host}"
        try:
            # Try to resolve the hostname
            socket.gethostbyname(pod_host)
            pods.append(pod_host)
            print(f"Discovered Bitcoin pod: {pod_host}")
        except socket.gaierror:
            # Host doesn't exist, stop looking
            if i == 0:
                print(f"Warning: No Bitcoin pods found starting from {pod_host}")
            break
    
    if not pods:
        print(f"Warning: No Bitcoin pods discovered for service {service_name} in namespace {namespace}")
    
    return pods

def get_pod_metrics(pod_host):
    """Get metrics for a specific Bitcoin pod"""
    try:
        # Get blockchain info
        data = make_bitcoin_rpc_call('getblockchaininfo', target_host=pod_host)
        if data:
            blocks = data.get('blocks', 0)
            difficulty = data.get('difficulty', 0)
            verification_progress = data.get('verificationprogress', 0)
        else:
            blocks = 0
            difficulty = 0
            verification_progress = 0
        
        # Get peer info
        peers = make_bitcoin_rpc_call('getpeerinfo', target_host=pod_host)
        if peers:
            peer_count = len(peers)
        else:
            peer_count = 0
        
        # Get network info
        network_data = make_bitcoin_rpc_call('getnetworkinfo', target_host=pod_host)
        if network_data:
            connections = network_data.get('connections', 0)
        else:
            connections = 0
        
        # Extract pod name from host
        pod_name = pod_host.split('.')[0]
        
        return {
            'pod': pod_name,
            'host': pod_host,
            'blocks': blocks,
            'peers': peer_count,
            'connections': connections,
            'difficulty': difficulty,
            'verification_progress': verification_progress,
            'healthy': data is not None
        }
    except Exception as e:
        pod_name = pod_host.split('.')[0]
        return {
            'pod': pod_name,
            'host': pod_host,
            'blocks': 0,
            'peers': 0,
            'connections': 0,
            'difficulty': 0,
            'verification_progress': 0,
            'healthy': False
        }

class BitcoinMetricsHandler(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path == '/metrics':
            try:
                # Discover all Bitcoin pods
                pods = discover_bitcoin_pods()
                
                if not pods:
                    # Fallback to single pod if discovery fails
                    service_name = os.getenv("BITCOIN_SERVICE_NAME", "bitcoin-stack")
                    namespace = os.getenv("BITCOIN_NAMESPACE", "bitcoin")
                    fallback_host = f"{service_name}-0.{service_name}.{namespace}.svc.cluster.local"
                    pods = [fallback_host]
                    print(f"Using fallback pod: {fallback_host}")
                
                print(f"Collecting metrics from {len(pods)} Bitcoin pods")
                
                # Get metrics from all pods in parallel
                all_metrics = []
                with ThreadPoolExecutor(max_workers=len(pods)) as executor:
                    future_to_pod = {executor.submit(get_pod_metrics, pod): pod for pod in pods}
                    for future in as_completed(future_to_pod):
                        metrics = future.result()
                        all_metrics.append(metrics)
                
                # Format Prometheus metrics
                metrics_output = ""
                
                for pod_metrics in all_metrics:
                    pod_name = pod_metrics['pod']
                    pod_label = f'pod="{pod_name}"'
                    
                    metrics_output += f"""# HELP bitcoin_blocks Current block height
# TYPE bitcoin_blocks gauge
bitcoin_blocks{{{pod_label}}} {pod_metrics['blocks']}
# HELP bitcoin_peers Number of connected peers
# TYPE bitcoin_peers gauge
bitcoin_peers{{{pod_label}}} {pod_metrics['peers']}
# HELP bitcoin_connections Number of network connections
# TYPE bitcoin_connections gauge
bitcoin_connections{{{pod_label}}} {pod_metrics['connections']}
# HELP bitcoin_difficulty Current network difficulty
# TYPE bitcoin_difficulty gauge
bitcoin_difficulty{{{pod_label}}} {pod_metrics['difficulty']}
# HELP bitcoin_verification_progress Blockchain verification progress (0-1)
# TYPE bitcoin_verification_progress gauge
bitcoin_verification_progress{{{pod_label}}} {pod_metrics['verification_progress']}
# HELP bitcoin_pod_healthy Bitcoin pod health status
# TYPE bitcoin_pod_healthy gauge
bitcoin_pod_healthy{{{pod_label}}} {1 if pod_metrics['healthy'] else 0}
"""
                
                self.send_response(200)
                self.send_header('Content-type', 'text/plain')
                self.end_headers()
                self.wfile.write(metrics_output.encode())
            except Exception as e:
                self.send_response(500)
                self.end_headers()
                self.wfile.write(f"Error: {str(e)}".encode())
        elif self.path == '/health':
            self.send_response(200)
            self.send_header('Content-type', 'text/plain')
            self.end_headers()
            self.wfile.write(b'OK')
        else:
            self.send_response(404)
            self.end_headers()

def signal_handler(sig, frame):
    print('Shutting down...')
    sys.exit(0)

if __name__ == "__main__":
    signal.signal(signal.SIGINT, signal_handler)
    signal.signal(signal.SIGTERM, signal_handler)
    
    PORT = 8000
    with socketserver.TCPServer(("", PORT), BitcoinMetricsHandler) as httpd:
        print(f"Bitcoin exporter serving at port {PORT}")
        httpd.serve_forever()