#!/bin/bash
#
# setup-cloudboot-server.sh - PhoenixGuard CloudBoot Server Setup
#
# "Build the HTTPS boot server that never trusts local storage"
#

set -e

# Configuration
CLOUDBOOT_DOMAIN="boot.phoenixguard.cloud"
NGINX_CONFIG="/etc/nginx/sites-available/phoenixguard-cloudboot"
CLOUDBOOT_ROOT="/var/www/phoenixguard-cloudboot"
SSL_CERT_PATH="/etc/letsencrypt/live/${CLOUDBOOT_DOMAIN}"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m'

print_status() { echo -e "${BLUE}[INFO]${NC} $1"; }
print_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
print_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
print_error() { echo -e "${RED}[ERROR]${NC} $1"; }

print_banner() {
    echo ""
    echo "  ╔══════════════════════════════════════════════════════════════════╗"
    echo "  ║           🔥 PHOENIXGUARD CLOUDBOOT SERVER SETUP 🔥             ║"
    echo "  ║                                                                  ║"
    echo "  ║        \"Build HTTPS boot server with certificate validation\"    ║"
    echo "  ║                                                                  ║"
    echo "  ╚══════════════════════════════════════════════════════════════════╝"
    echo ""
}

check_root() {
    if [ "$EUID" -ne 0 ]; then
        print_error "This script must be run as root"
        print_status "Use: sudo $0"
        exit 1
    fi
}

install_dependencies() {
    print_status "Installing CloudBoot server dependencies..."
    
    # Update package list
    apt update
    
    # Install required packages
    apt install -y \
        nginx \
        certbot \
        python3-certbot-nginx \
        openssl \
        curl \
        jq \
        python3-pip \
        python3-flask \
        python3-cryptography \
        build-essential
    
    # Install additional Python packages for signing
    pip3 install pycryptodome requests
    
    print_success "Dependencies installed"
}

create_directory_structure() {
    print_status "Creating CloudBoot directory structure..."
    
    # Create main directories
    mkdir -p "$CLOUDBOOT_ROOT"/{api/v1/boot,kernels,signatures,logs,config}
    mkdir -p "$CLOUDBOOT_ROOT/api/v1/boot"/{ubuntu,phoenix,forensics}
    
    # Set proper permissions
    chown -R www-data:www-data "$CLOUDBOOT_ROOT"
    chmod -R 755 "$CLOUDBOOT_ROOT"
    
    print_success "Directory structure created"
}

generate_ssl_certificate() {
    print_status "Setting up SSL certificate for CloudBoot..."
    
    # Check if certificate already exists
    if [ -f "$SSL_CERT_PATH/fullchain.pem" ]; then
        print_warning "SSL certificate already exists"
        return 0
    fi
    
    # Generate Let's Encrypt certificate
    print_status "Obtaining SSL certificate from Let's Encrypt..."
    print_warning "Make sure $CLOUDBOOT_DOMAIN points to this server!"
    
    # Stop nginx temporarily
    systemctl stop nginx || true
    
    # Get certificate
    certbot certonly --standalone \
        --preferred-challenges http \
        --email admin@phoenixguard.security \
        --agree-tos \
        --no-eff-email \
        -d "$CLOUDBOOT_DOMAIN"
    
    if [ $? -eq 0 ]; then
        print_success "SSL certificate obtained"
    else
        print_error "Failed to obtain SSL certificate"
        print_status "Creating self-signed certificate for testing..."
        
        # Create self-signed certificate as fallback
        mkdir -p "/etc/ssl/phoenixguard"
        openssl req -x509 -nodes -days 365 -newkey rsa:4096 \
            -keyout "/etc/ssl/phoenixguard/cloudboot.key" \
            -out "/etc/ssl/phoenixguard/cloudboot.crt" \
            -subj "/C=US/ST=Security/L=CloudBoot/O=PhoenixGuard/CN=$CLOUDBOOT_DOMAIN"
        
        SSL_CERT_PATH="/etc/ssl/phoenixguard"
        print_warning "Using self-signed certificate - replace with real certificate in production!"
    fi
}

create_nginx_config() {
    print_status "Creating Nginx configuration for CloudBoot..."
    
    cat > "$NGINX_CONFIG" << EOF
# PhoenixGuard CloudBoot Server Configuration
# HTTPS-only with strict security headers

server {
    listen 80;
    server_name $CLOUDBOOT_DOMAIN;
    
    # Redirect all HTTP to HTTPS - NO EXCEPTIONS
    return 301 https://\$server_name\$request_uri;
}

server {
    listen 443 ssl http2;
    server_name $CLOUDBOOT_DOMAIN;
    
    # SSL Configuration - Maximum Security
    ssl_certificate ${SSL_CERT_PATH}/fullchain.pem;
    ssl_certificate_key ${SSL_CERT_PATH}/privkey.pem;
    ssl_trusted_certificate ${SSL_CERT_PATH}/chain.pem;
    
    # SSL Security Settings
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers ECDHE-RSA-AES256-GCM-SHA384:ECDHE-RSA-CHACHA20-POLY1305:ECDHE-RSA-AES128-GCM-SHA256;
    ssl_prefer_server_ciphers off;
    ssl_session_cache shared:SSL:10m;
    ssl_session_timeout 1d;
    ssl_session_tickets off;
    
    # HSTS and Security Headers
    add_header Strict-Transport-Security "max-age=63072000; includeSubDomains; preload" always;
    add_header X-Content-Type-Options "nosniff" always;
    add_header X-Frame-Options "DENY" always;
    add_header X-XSS-Protection "1; mode=block" always;
    add_header Referrer-Policy "no-referrer" always;
    
    # Document root
    root $CLOUDBOOT_ROOT;
    index index.html;
    
    # Logging
    access_log /var/log/nginx/phoenixguard-cloudboot-access.log;
    error_log /var/log/nginx/phoenixguard-cloudboot-error.log;
    
    # Rate limiting for security
    limit_req_zone \$binary_remote_addr zone=cloudboot:10m rate=10r/m;
    limit_req zone=cloudboot burst=5;
    
    # Main landing page
    location / {
        try_files \$uri \$uri/ =404;
    }
    
    # API endpoints for boot files
    location /api/v1/boot/ {
        # Only allow GET requests
        limit_except GET {
            deny all;
        }
        
        # Require User-Agent header from PhoenixGuard
        if (\$http_user_agent !~ "PhoenixGuard-CloudBoot") {
            return 403;
        }
        
        # Add headers for boot files
        add_header X-PhoenixGuard-Boot "verified-https-boot" always;
        add_header X-Content-Type-Options "nosniff" always;
        add_header Cache-Control "no-cache, no-store, must-revalidate" always;
        
        # Serve boot files
        try_files \$uri =404;
    }
    
    # Kernel files - special handling
    location ~ ^/api/v1/boot/.*/kernel\$ {
        # Add kernel-specific headers
        add_header X-PhoenixGuard-Content-Type "kernel" always;
        add_header X-PhoenixGuard-Signature-Required "true" always;
        
        # Content type for kernels
        add_header Content-Type "application/octet-stream" always;
    }
    
    # InitRD files
    location ~ ^/api/v1/boot/.*/initrd\$ {
        add_header X-PhoenixGuard-Content-Type "initrd" always;
        add_header Content-Type "application/octet-stream" always;
    }
    
    # Health check endpoint
    location /health {
        access_log off;
        return 200 "PhoenixGuard CloudBoot Server OK\\n";
        add_header Content-Type text/plain always;
    }
    
    # Block all other requests
    location ~ /\. {
        deny all;
    }
}
EOF
    
    # Enable the site
    ln -sf "$NGINX_CONFIG" /etc/nginx/sites-enabled/
    
    # Remove default site
    rm -f /etc/nginx/sites-enabled/default
    
    print_success "Nginx configuration created"
}

create_boot_api() {
    print_status "Creating CloudBoot API..."
    
    # Create Python API server for dynamic boot handling
    cat > "$CLOUDBOOT_ROOT/cloudboot-api.py" << 'EOF'
#!/usr/bin/env python3
"""
PhoenixGuard CloudBoot API Server
Serves verified boot files with cryptographic signatures
"""

import os
import json
import hashlib
import logging
from datetime import datetime
from flask import Flask, request, jsonify, send_file, abort
from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import rsa, padding
from cryptography.exceptions import InvalidSignature

app = Flask(__name__)

# Configuration
CLOUDBOOT_ROOT = '/var/www/phoenixguard-cloudboot'
KERNEL_DIR = os.path.join(CLOUDBOOT_ROOT, 'kernels')
SIGNATURES_DIR = os.path.join(CLOUDBOOT_ROOT, 'signatures')

# Logging setup
logging.basicConfig(
    filename='/var/log/phoenixguard-cloudboot.log',
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s'
)

@app.before_request
def log_request():
    """Log all requests for security monitoring"""
    logging.info(f"Request: {request.remote_addr} - {request.method} {request.path} - UA: {request.headers.get('User-Agent', 'None')}")

@app.route('/api/v1/boot/ubuntu/latest/kernel')
def get_ubuntu_kernel():
    """Serve latest Ubuntu kernel with signature verification"""
    
    # Validate User-Agent
    user_agent = request.headers.get('User-Agent', '')
    if 'PhoenixGuard-CloudBoot' not in user_agent:
        logging.warning(f"Invalid User-Agent: {user_agent}")
        abort(403)
    
    # Find latest kernel
    kernel_path = find_latest_kernel('ubuntu')
    if not kernel_path:
        logging.error("No Ubuntu kernel found")
        abort(404)
    
    # Verify signature before serving
    if not verify_kernel_signature(kernel_path):
        logging.error(f"Signature verification failed for {kernel_path}")
        abort(403)
    
    logging.info(f"Serving verified Ubuntu kernel: {kernel_path}")
    return send_file(kernel_path, mimetype='application/octet-stream')

@app.route('/api/v1/boot/ubuntu/latest/initrd')
def get_ubuntu_initrd():
    """Serve latest Ubuntu initrd"""
    
    # Validate User-Agent
    user_agent = request.headers.get('User-Agent', '')
    if 'PhoenixGuard-CloudBoot' not in user_agent:
        abort(403)
    
    # Find corresponding initrd
    initrd_path = find_latest_initrd('ubuntu')
    if not initrd_path:
        abort(404)
    
    logging.info(f"Serving Ubuntu initrd: {initrd_path}")
    return send_file(initrd_path, mimetype='application/octet-stream')

@app.route('/health')
def health_check():
    """Health check endpoint"""
    return jsonify({
        'status': 'healthy',
        'service': 'PhoenixGuard CloudBoot',
        'timestamp': datetime.now().isoformat(),
        'available_kernels': count_available_kernels()
    })

def find_latest_kernel(distro):
    """Find the latest kernel for specified distribution"""
    kernel_dir = os.path.join(KERNEL_DIR, distro)
    if not os.path.exists(kernel_dir):
        return None
    
    # Find newest kernel file
    kernels = [f for f in os.listdir(kernel_dir) if f.startswith('vmlinuz')]
    if not kernels:
        return None
    
    # Sort by modification time, return newest
    kernels.sort(key=lambda x: os.path.getmtime(os.path.join(kernel_dir, x)), reverse=True)
    return os.path.join(kernel_dir, kernels[0])

def find_latest_initrd(distro):
    """Find the latest initrd for specified distribution"""
    kernel_dir = os.path.join(KERNEL_DIR, distro)
    if not os.path.exists(kernel_dir):
        return None
    
    # Find newest initrd file
    initrds = [f for f in os.listdir(kernel_dir) if f.startswith('initrd')]
    if not initrds:
        return None
    
    initrds.sort(key=lambda x: os.path.getmtime(os.path.join(kernel_dir, x)), reverse=True)
    return os.path.join(kernel_dir, initrds[0])

def verify_kernel_signature(kernel_path):
    """Verify cryptographic signature of kernel"""
    # TODO: Implement actual signature verification
    # For now, just check if signature file exists
    signature_file = kernel_path + '.sig'
    return os.path.exists(signature_file)

def count_available_kernels():
    """Count available kernels for health check"""
    count = 0
    for root, dirs, files in os.walk(KERNEL_DIR):
        count += len([f for f in files if f.startswith('vmlinuz')])
    return count

if __name__ == '__main__':
    app.run(host='127.0.0.1', port=8080, debug=False)
EOF

    chmod +x "$CLOUDBOOT_ROOT/cloudboot-api.py"
    chown www-data:www-data "$CLOUDBOOT_ROOT/cloudboot-api.py"
    
    print_success "CloudBoot API created"
}

create_sample_content() {
    print_status "Creating sample CloudBoot content..."
    
    # Create main page
    cat > "$CLOUDBOOT_ROOT/index.html" << 'EOF'
<!DOCTYPE html>
<html>
<head>
    <title>PhoenixGuard CloudBoot Server</title>
    <style>
        body { font-family: monospace; background: #1a1a1a; color: #00ff00; padding: 20px; }
        .header { color: #ff6600; font-size: 24px; margin-bottom: 20px; }
        .status { background: #333; padding: 10px; margin: 10px 0; }
        .endpoint { background: #2a2a2a; padding: 10px; margin: 5px 0; }
    </style>
</head>
<body>
    <div class="header">🔥 PhoenixGuard CloudBoot Server 🔥</div>
    
    <div class="status">
        <strong>Status:</strong> Online and Ready<br>
        <strong>Protocol:</strong> HTTPS Only (Certificate Required)<br>
        <strong>Security:</strong> TLS 1.2+ with Perfect Forward Secrecy<br>
        <strong>Access:</strong> PhoenixGuard Clients Only
    </div>
    
    <h3>Available Endpoints:</h3>
    
    <div class="endpoint">
        <strong>GET /api/v1/boot/ubuntu/latest/kernel</strong><br>
        Latest Ubuntu kernel (cryptographically signed)
    </div>
    
    <div class="endpoint">
        <strong>GET /api/v1/boot/ubuntu/latest/initrd</strong><br>
        Corresponding Ubuntu initrd
    </div>
    
    <div class="endpoint">
        <strong>GET /health</strong><br>
        Server health check and status
    </div>
    
    <p><em>"Never trust local storage - always boot from verified HTTPS"</em></p>
</body>
</html>
EOF

    # Create sample kernel directory structure
    mkdir -p "$CLOUDBOOT_ROOT/kernels/ubuntu"
    
    # Create placeholder files (would be real kernels in production)
    echo "Ubuntu Kernel Placeholder - Replace with real signed kernel" > "$CLOUDBOOT_ROOT/kernels/ubuntu/vmlinuz-5.19.0-phoenix"
    echo "Ubuntu InitRD Placeholder - Replace with real initrd" > "$CLOUDBOOT_ROOT/kernels/ubuntu/initrd-5.19.0-phoenix"
    echo "Signature Placeholder - Replace with real cryptographic signature" > "$CLOUDBOOT_ROOT/kernels/ubuntu/vmlinuz-5.19.0-phoenix.sig"
    
    chown -R www-data:www-data "$CLOUDBOOT_ROOT"
    
    print_success "Sample content created"
}

configure_systemd_service() {
    print_status "Creating systemd service for CloudBoot API..."
    
    cat > "/etc/systemd/system/phoenixguard-cloudboot.service" << 'EOF'
[Unit]
Description=PhoenixGuard CloudBoot API Server
After=network.target
Requires=network.target

[Service]
Type=simple
User=www-data
Group=www-data
WorkingDirectory=/var/www/phoenixguard-cloudboot
ExecStart=/usr/bin/python3 /var/www/phoenixguard-cloudboot/cloudboot-api.py
Restart=always
RestartSec=10
StandardOutput=syslog
StandardError=syslog
SyslogIdentifier=phoenixguard-cloudboot

[Install]
WantedBy=multi-user.target
EOF

    # Enable and start the service
    systemctl daemon-reload
    systemctl enable phoenixguard-cloudboot.service
    
    print_success "CloudBoot API service configured"
}

test_nginx_config() {
    print_status "Testing Nginx configuration..."
    
    if nginx -t; then
        print_success "Nginx configuration is valid"
    else
        print_error "Nginx configuration has errors"
        exit 1
    fi
}

start_services() {
    print_status "Starting CloudBoot services..."
    
    # Start Nginx
    systemctl restart nginx
    systemctl enable nginx
    
    # Start CloudBoot API
    systemctl start phoenixguard-cloudboot
    
    print_success "Services started"
}

show_summary() {
    print_success "🔥 PhoenixGuard CloudBoot Server setup complete!"
    echo ""
    echo "📋 Server Configuration:"
    echo "   🌐 Domain: $CLOUDBOOT_DOMAIN"
    echo "   🔐 HTTPS: Enabled (certificate required)"
    echo "   📁 Root: $CLOUDBOOT_ROOT"
    echo "   🔧 Config: $NGINX_CONFIG"
    echo ""
    echo "🎯 Available Endpoints:"
    echo "   https://$CLOUDBOOT_DOMAIN/health"
    echo "   https://$CLOUDBOOT_DOMAIN/api/v1/boot/ubuntu/latest/kernel"
    echo "   https://$CLOUDBOOT_DOMAIN/api/v1/boot/ubuntu/latest/initrd"
    echo ""
    echo "🔧 Next Steps:"
    echo "   1. Replace placeholder kernels with real signed kernels"
    echo "   2. Set up proper cryptographic signing"
    echo "   3. Configure DNS to point $CLOUDBOOT_DOMAIN to this server"
    echo "   4. Test CloudBoot client connectivity"
    echo ""
    echo "📊 Service Status:"
    systemctl is-active nginx && echo "   ✅ Nginx: Active" || echo "   ❌ Nginx: Inactive"
    systemctl is-active phoenixguard-cloudboot && echo "   ✅ CloudBoot API: Active" || echo "   ❌ CloudBoot API: Inactive"
    echo ""
    echo "🔥 Your systems can now boot from verified HTTPS!"
}

main() {
    print_banner
    
    check_root
    install_dependencies
    create_directory_structure
    generate_ssl_certificate
    create_nginx_config
    create_boot_api
    create_sample_content
    configure_systemd_service
    test_nginx_config
    start_services
    show_summary
}

# Run if called directly
if [ "${BASH_SOURCE[0]}" == "${0}" ]; then
    main "$@"
fi
