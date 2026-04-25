#!/usr/bin/env bash
# =============================================================================
#  LLM API Gateway — One-Click Deploy Script
#  Supports: Ubuntu 20.04+, Debian 11+, CentOS 8+
# =============================================================================
set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; BOLD='\033[1m'; NC='\033[0m'

info()    { echo -e "${BLUE}[INFO]${NC}  $*"; }
success() { echo -e "${GREEN}[OK]${NC}    $*"; }
warn()    { echo -e "${YELLOW}[WARN]${NC}  $*"; }
error()   { echo -e "${RED}[ERROR]${NC} $*"; exit 1; }

banner() {
cat <<'EOF'

  ██╗     ██╗     ███╗   ███╗  ██████╗  ██████╗ ████████╗
  ██║     ██║     ████╗ ████║ ██╔════╝ ██╔══██╗╚══██╔══╝
  ██║     ██║     ██╔████╔██║ ██║  ███╗███████║   ██║   
  ██║     ██║     ██║╚██╔╝██║ ██║   ██║██╔══██║   ██║   
  ███████╗███████╗██║ ╚═╝ ██║ ╚██████╔╝██║  ██║   ██║   
  ╚══════╝╚══════╝╚═╝     ╚═╝  ╚═════╝ ╚═╝  ╚═╝   ╚═╝   
         API Gateway — One-Click Deploy
EOF
}

# ─── Detect OS ────────────────────────────────────────────────────────────────
detect_os() {
    if   [[ -f /etc/debian_version ]]; then echo "debian"
    elif [[ -f /etc/redhat-release ]];  then echo "rhel"
    else error "Unsupported OS. Please use Ubuntu/Debian/CentOS."
    fi
}

# ─── Install Docker ───────────────────────────────────────────────────────────
install_docker() {
    if command -v docker &>/dev/null; then
        success "Docker already installed: $(docker --version)"
        return
    fi

    info "Installing Docker..."
    OS=$(detect_os)

    if [[ "$OS" == "debian" ]]; then
        apt-get update -qq
        apt-get install -y -qq ca-certificates curl gnupg lsb-release
        curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /usr/share/keyrings/docker.gpg
        echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker.gpg] \
            https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" \
            > /etc/apt/sources.list.d/docker.list
        apt-get update -qq
        apt-get install -y -qq docker-ce docker-ce-cli containerd.io docker-compose-plugin
    else
        dnf config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo
        dnf install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin
    fi

    systemctl enable --now docker
    success "Docker installed successfully"
}

# ─── Check GPU ────────────────────────────────────────────────────────────────
check_gpu() {
    if command -v nvidia-smi &>/dev/null && nvidia-smi &>/dev/null; then
        GPU_COUNT=$(nvidia-smi --query-gpu=name --format=csv,noheader | wc -l)
        success "NVIDIA GPU detected: $GPU_COUNT GPU(s)"
        GPU_MODE=true
    else
        warn "No NVIDIA GPU detected — will run in CPU mode (slower)"
        GPU_MODE=false
    fi
}

# ─── Generate SSL certs (self-signed for dev) ─────────────────────────────────
generate_certs() {
    CERT_DIR="./nginx/certs"
    mkdir -p "$CERT_DIR"

    if [[ -f "$CERT_DIR/cert.pem" ]]; then
        success "SSL certificates already exist"
        return
    fi

    info "Generating self-signed SSL certificates..."
    openssl req -x509 -nodes -newkey rsa:4096 \
        -keyout "$CERT_DIR/key.pem" \
        -out    "$CERT_DIR/cert.pem" \
        -days 365 \
        -subj "/CN=llm-api-gateway/O=LLM Gateway/C=CN" \
        -addext "subjectAltName=IP:$(hostname -I | awk '{print $1}'),DNS:localhost" \
        2>/dev/null
    success "SSL certificates generated"
}

# ─── Setup .env ───────────────────────────────────────────────────────────────
setup_env() {
    if [[ -f ".env" ]]; then
        warn ".env file already exists, skipping"
        return
    fi

    SECRET=$(openssl rand -hex 32)
    TRACKER_KEY=$(openssl rand -hex 16)

    cp .env.example .env
    sed -i "s/your-super-secret-key-here/$SECRET/"        .env
    sed -i "s/tracker-secret-change-me/$TRACKER_KEY/"     .env

    success ".env configured with random secrets"
    info    "Tracker API key saved to .env"
}

# ─── Disable GPU in compose if no GPU ─────────────────────────────────────────
patch_compose_for_cpu() {
    if [[ "$GPU_MODE" == "false" ]]; then
        info "Patching docker-compose.yml for CPU-only mode..."
        # Remove the deploy/resources section from ollama service
        python3 - <<'PYEOF'
import re, sys
with open("docker-compose.yml") as f:
    content = f.read()
# Remove GPU deploy block
content = re.sub(r'\n    # GPU.*?capabilities: \[gpu\]\n', '\n', content, flags=re.DOTALL)
with open("docker-compose.yml", "w") as f:
    f.write(content)
print("  Patched: GPU section removed")
PYEOF
    fi
}

# ─── Pull model ───────────────────────────────────────────────────────────────
pull_model() {
    MODEL=${1:-"qwen2.5:7b"}
    info "Pulling model: $MODEL (this may take a while...)"
    docker exec ollama ollama pull "$MODEL" && success "Model $MODEL ready"
}

# ─── Main ─────────────────────────────────────────────────────────────────────
main() {
    banner

    # Must run as root or with sudo
    [[ $EUID -eq 0 ]] || error "Please run as root: sudo ./deploy.sh"

    info "Starting deployment..."

    install_docker
    check_gpu
    generate_certs
    setup_env
    patch_compose_for_cpu

    info "Pulling Docker images..."
    docker compose pull

    info "Starting services..."
    docker compose up -d

    # Wait for Ollama to be healthy
    info "Waiting for Ollama to be ready..."
    for i in $(seq 1 30); do
        if docker exec ollama curl -sf http://localhost:11434/api/tags &>/dev/null; then
            success "Ollama is ready"
            break
        fi
        sleep 3
        echo -n "."
    done

    # Pull default model
    DEFAULT_MODEL=${MODEL:-"qwen2.5:7b"}
    pull_model "$DEFAULT_MODEL"

    # Print summary
    SERVER_IP=$(hostname -I | awk '{print $1}')

    echo ""
    echo -e "${BOLD}════════════════════════════════════════════════════${NC}"
    echo -e "${GREEN}${BOLD}  ✅  Deployment Complete!${NC}"
    echo -e "${BOLD}════════════════════════════════════════════════════${NC}"
    echo ""
    echo -e "  ${BOLD}Web UI:${NC}        https://$SERVER_IP"
    echo -e "  ${BOLD}API Base:${NC}       https://$SERVER_IP/v1"
    echo -e "  ${BOLD}Usage Stats:${NC}    https://$SERVER_IP/usage/stats/summary"
    echo -e "  ${BOLD}Ollama:${NC}         http://$SERVER_IP:11434"
    echo ""
    echo -e "  ${BOLD}Default model:${NC}  $DEFAULT_MODEL"
    echo -e "  ${BOLD}GPU mode:${NC}       $GPU_MODE"
    echo ""
    echo -e "  ${YELLOW}Next steps:${NC}"
    echo -e "  1. Open Web UI → Settings → API Keys → Create new key"
    echo -e "  2. Share the API key with clients"
    echo -e "  3. Clients connect using OpenAI SDK pointing to:"
    echo -e "     base_url='https://$SERVER_IP/v1'"
    echo ""
    echo -e "  ${BLUE}Tracker key:${NC} $(grep TRACKER_API_KEY .env | cut -d= -f2)"
    echo ""
}

main "$@"
