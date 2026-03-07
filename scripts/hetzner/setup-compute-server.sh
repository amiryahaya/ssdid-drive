#!/bin/bash
#
# SecureSharing - Compute Server Setup Script
# Run this on Hetzner AX52 (Compute Server)
#
# Usage: sudo ./setup-compute-server.sh
#

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

print_header() {
    echo ""
    echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"
    echo -e "${BLUE}  $1${NC}"
    echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"
    echo ""
}

print_step() { echo -e "${GREEN}▶${NC} $1"; }
print_warning() { echo -e "${YELLOW}⚠${NC} $1"; }
print_error() { echo -e "${RED}✗${NC} $1"; }

# Check if root
if [ "$EUID" -ne 0 ]; then
    print_error "Please run as root (sudo)"
    exit 1
fi

print_header "SecureSharing Compute Server Setup"

# Configuration
read -p "Enter Data Server Private IP [10.0.0.2]: " DATA_SERVER_IP
DATA_SERVER_IP=${DATA_SERVER_IP:-10.0.0.2}

read -p "Enter your domain name: " DOMAIN_NAME
if [ -z "$DOMAIN_NAME" ]; then
    print_error "Domain name is required"
    exit 1
fi

read -p "Enter your SSH IP for firewall [detected]: " SSH_IP
SSH_IP=${SSH_IP:-$(echo $SSH_CONNECTION | awk '{print $1}')}

# ============================================================================
# Phase 1: System Setup
# ============================================================================

print_header "Phase 1: System Setup"

print_step "Updating system..."
apt update && apt upgrade -y

print_step "Installing common packages..."
apt install -y \
    curl wget git htop tmux vim \
    ufw fail2ban \
    build-essential \
    unzip jq

print_step "Setting timezone..."
timedatectl set-timezone UTC

print_step "Setting hostname..."
hostnamectl set-hostname compute.securesharing.internal

print_step "Configuring /etc/hosts..."
cat >> /etc/hosts << EOF
10.0.0.1    compute.securesharing.internal compute
$DATA_SERVER_IP    data.securesharing.internal data
EOF

# ============================================================================
# Phase 2: Firewall
# ============================================================================

print_header "Phase 2: Firewall Configuration"

print_step "Configuring UFW..."
ufw default deny incoming
ufw default allow outgoing
ufw allow from $SSH_IP to any port 22 comment 'SSH from admin'
ufw allow 80/tcp comment 'HTTP'
ufw allow 443/tcp comment 'HTTPS'
ufw allow from 10.0.0.0/24 comment 'Private network'

print_step "Enabling firewall..."
echo "y" | ufw enable
ufw status

# ============================================================================
# Phase 3: Install Erlang & Elixir
# ============================================================================

print_header "Phase 3: Installing Erlang & Elixir"

print_step "Adding Erlang repository..."
apt install -y gnupg
wget https://packages.erlang-solutions.com/erlang-solutions_2.0_all.deb
dpkg -i erlang-solutions_2.0_all.deb
rm erlang-solutions_2.0_all.deb
apt update

print_step "Installing Erlang and Elixir..."
apt install -y esl-erlang elixir

elixir --version

# ============================================================================
# Phase 4: Install Node.js
# ============================================================================

print_header "Phase 4: Installing Node.js"

print_step "Installing Node.js 20..."
curl -fsSL https://deb.nodesource.com/setup_20.x | bash -
apt install -y nodejs

node --version
npm --version

# ============================================================================
# Phase 5: Install Python & Presidio
# ============================================================================

print_header "Phase 5: Installing Python & Presidio"

print_step "Installing Python..."
apt install -y python3 python3-pip python3-venv

print_step "Creating Presidio environment..."
python3 -m venv /opt/presidio
source /opt/presidio/bin/activate

print_step "Installing Presidio (this may take a while)..."
pip install --upgrade pip
pip install presidio-analyzer presidio-anonymizer flask gunicorn
python -m spacy download en_core_web_lg

print_step "Creating Presidio service script..."
cat > /opt/presidio/run.py << 'EOF'
from presidio_analyzer import AnalyzerEngine
from flask import Flask, request, jsonify

app = Flask(__name__)
analyzer = AnalyzerEngine()

@app.route('/health', methods=['GET'])
def health():
    return jsonify({"status": "healthy"})

@app.route('/analyze', methods=['POST'])
def analyze():
    data = request.json
    results = analyzer.analyze(
        text=data.get('text', ''),
        language=data.get('language', 'en'),
        entities=data.get('entities')
    )
    return jsonify([r.to_dict() for r in results])

if __name__ == '__main__':
    app.run(host='127.0.0.1', port=5002)
EOF

deactivate

print_step "Creating Presidio systemd service..."
cat > /etc/systemd/system/presidio.service << 'EOF'
[Unit]
Description=Presidio NER Service
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=/opt/presidio
ExecStart=/opt/presidio/bin/gunicorn -w 2 -b 127.0.0.1:5002 run:app
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable presidio
systemctl start presidio

# ============================================================================
# Phase 6: Install llama.cpp & Qwen
# ============================================================================

print_header "Phase 6: Installing llama.cpp & Qwen2.5-14B"

print_step "Building llama.cpp..."
cd /opt
git clone https://github.com/ggerganov/llama.cpp
cd llama.cpp
make -j$(nproc) GGML_NATIVE=ON

print_step "Downloading Qwen2.5-14B model (this will take a while)..."
mkdir -p /opt/models
cd /opt/models

if [ ! -f "qwen2.5-14b-instruct-q4_k_m.gguf" ]; then
    wget -c https://huggingface.co/Qwen/Qwen2.5-14B-Instruct-GGUF/resolve/main/qwen2.5-14b-instruct-q4_k_m.gguf
fi

print_step "Creating llama-server systemd service..."
cat > /etc/systemd/system/llama-server.service << 'EOF'
[Unit]
Description=LLaMA.cpp Server (Qwen2.5-14B)
After=network.target

[Service]
Type=simple
User=root
ExecStart=/opt/llama.cpp/llama-server \
  -m /opt/models/qwen2.5-14b-instruct-q4_k_m.gguf \
  --host 127.0.0.1 \
  --port 8080 \
  -c 4096 \
  -t 12 \
  --parallel 2
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable llama-server
systemctl start llama-server

# ============================================================================
# Phase 7: Create App User & Directories
# ============================================================================

print_header "Phase 7: Setting Up Application User"

print_step "Creating securesharing user..."
useradd -r -m -s /bin/bash securesharing || true

print_step "Creating directories..."
mkdir -p /home/securesharing/app
mkdir -p /opt/scripts
chown -R securesharing:securesharing /home/securesharing

# ============================================================================
# Phase 8: Install Nginx
# ============================================================================

print_header "Phase 8: Installing Nginx"

print_step "Installing Nginx..."
apt install -y nginx certbot python3-certbot-nginx

print_step "Creating Nginx configuration..."
cat > /etc/nginx/sites-available/securesharing << EOF
upstream backend {
    server 127.0.0.1:4000;
}

upstream pii_service {
    server 127.0.0.1:4001;
}

server {
    listen 80;
    server_name $DOMAIN_NAME;

    location / {
        proxy_pass http://backend;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }

    location /pii/ {
        rewrite ^/pii/(.*) /\$1 break;
        proxy_pass http://pii_service;
        proxy_http_version 1.1;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
    }

    location /live {
        proxy_pass http://backend;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host \$host;
        proxy_read_timeout 86400;
    }
}
EOF

ln -sf /etc/nginx/sites-available/securesharing /etc/nginx/sites-enabled/
rm -f /etc/nginx/sites-enabled/default

nginx -t
systemctl reload nginx

print_warning "Run 'certbot --nginx -d $DOMAIN_NAME' after DNS is configured"

# ============================================================================
# Phase 9: Create Health Check Script
# ============================================================================

print_header "Phase 9: Creating Utility Scripts"

cat > /opt/scripts/healthcheck.sh << 'EOF'
#!/bin/bash

check_service() {
    if systemctl is-active --quiet $1; then
        echo "✓ $1 is running"
        return 0
    else
        echo "✗ $1 is NOT running"
        return 1
    fi
}

check_http() {
    if curl -sf "$1" > /dev/null 2>&1; then
        echo "✓ $2 is responding"
        return 0
    else
        echo "✗ $2 is NOT responding"
        return 1
    fi
}

echo "=== Service Status ==="
check_service presidio
check_service llama-server
check_service nginx

echo ""
echo "=== HTTP Endpoints ==="
check_http "http://localhost:5002/health" "Presidio"
check_http "http://localhost:8080/health" "LLM Server"

echo ""
echo "=== Data Server ==="
nc -z data.securesharing.internal 5432 && echo "✓ PostgreSQL reachable" || echo "✗ PostgreSQL NOT reachable"
nc -z data.securesharing.internal 3900 && echo "✓ Garage S3 reachable" || echo "✗ Garage S3 NOT reachable"
EOF

chmod +x /opt/scripts/healthcheck.sh

# ============================================================================
# Summary
# ============================================================================

print_header "Setup Complete!"

echo "Services installed:"
echo "  ✓ Elixir $(elixir --version | head -1)"
echo "  ✓ Node.js $(node --version)"
echo "  ✓ Presidio (port 5002)"
echo "  ✓ llama-server with Qwen2.5-14B (port 8080)"
echo "  ✓ Nginx (ports 80, 443)"
echo ""
echo "Next steps:"
echo "  1. Clone your repository to /home/securesharing/app"
echo "  2. Configure environment files"
echo "  3. Run migrations"
echo "  4. Create systemd services for backend and pii-service"
echo "  5. Run: certbot --nginx -d $DOMAIN_NAME"
echo ""
echo "Health check: /opt/scripts/healthcheck.sh"
echo ""
