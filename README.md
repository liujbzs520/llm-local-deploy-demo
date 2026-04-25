# 🤖 LLM API Gateway

> **Self-hosted LLM service platform** — Deploy open-source models on your own server and expose a fully OpenAI-compatible API. Built with Ollama + Open WebUI + Nginx.

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![Docker](https://img.shields.io/badge/Docker-Compose-blue?logo=docker)](docker-compose.yml)
[![OpenAI Compatible](https://img.shields.io/badge/API-OpenAI%20Compatible-green)](examples/)

---

## 🏗️ Architecture

```
Client (OpenAI SDK)
        │
        ▼
┌───────────────┐
│  Nginx Gateway │  ← Rate limiting, SSL termination, access logs
│  (Port 80/443) │
└───────┬───────┘
        │
   ┌────┴────────────────┐
   │                     │
   ▼                     ▼
┌──────────┐     ┌───────────────┐
│Open WebUI│     │ Usage Tracker │  ← Token counting, per-key billing stats
│:3000     │     │ :8001         │
└────┬─────┘     └───────────────┘
     │
     ▼
┌──────────┐
│  Ollama  │  ← Local model inference (GPU/CPU)
│  :11434  │
└──────────┘
```

## ✨ Features

| Feature | Description |
|---|---|
| 🚀 **One-click deploy** | Single shell script sets up everything |
| 🔑 **API key management** | Issue keys to clients via Open WebUI |
| 📊 **Usage tracking** | Per-key token consumption & cost estimates |
| 🔒 **SSL / HTTPS** | Auto-generated self-signed certs (bring your own for prod) |
| ⚡ **GPU support** | NVIDIA GPU auto-detected; falls back to CPU |
| 🌐 **OpenAI-compatible** | Drop-in replacement — clients use standard OpenAI SDK |
| 🐳 **Fully containerized** | Docker Compose, zero host dependencies |

## 🚀 Quick Start

### Prerequisites

- Ubuntu 20.04+ / Debian 11+ / CentOS 8+ server
- At least 16 GB RAM (32 GB recommended for 7B+ models)
- NVIDIA GPU + drivers (optional but recommended)
- Ports 80, 443, 3000, 11434 open on firewall

### Deploy in 3 steps

```bash
# 1. Clone this repo
git clone https://github.com/YOUR_USERNAME/llm-api-gateway.git
cd llm-api-gateway

# 2. Run the deploy script (handles Docker install, certs, env setup)
sudo bash deploy.sh

# 3. Done! Visit https://YOUR_SERVER_IP to access the Web UI
```

The script will:
- Install Docker if needed
- Detect GPU and configure accordingly
- Generate SSL certificates
- Create `.env` with random secrets
- Pull Docker images and start all services
- Download the default model (`qwen2.5:7b`)

### Pull additional models

```bash
# Any model from ollama.com/library
docker exec ollama ollama pull llama3.1:8b
docker exec ollama ollama pull deepseek-r1:7b
docker exec ollama ollama pull mistral:7b
```

## 🔑 Issuing API Keys to Clients

1. Open `https://YOUR_SERVER_IP` → Log in as admin
2. Go to **Settings → API Keys → Create New Key**
3. Set a label (e.g. client name) and optionally a rate limit
4. Share the key with your client

## 👩‍💻 Client Integration

Clients connect using the standard **OpenAI SDK** — no custom library needed:

```python
from openai import OpenAI

client = OpenAI(
    base_url="https://YOUR_SERVER_IP/v1",
    api_key="sk-your-issued-api-key",
)

response = client.chat.completions.create(
    model="qwen2.5:7b",
    messages=[{"role": "user", "content": "Hello!"}],
)
print(response.choices[0].message.content)
```

See [`examples/client_example.py`](examples/client_example.py) for streaming and more.

## 📊 Usage & Billing Dashboard

Query token consumption per API key:

```bash
# Replace with your TRACKER_API_KEY from .env
curl https://YOUR_SERVER_IP/usage/stats/summary \
  -H "x-tracker-key: YOUR_TRACKER_KEY"
```

Response:
```json
{
  "total_calls": 1523,
  "total_tokens": 4820000,
  "total_cost_usd": 9.64,
  "by_api_key": [
    { "api_key": "sk-abc...", "calls": 800, "tokens": 2500000, "cost": 5.00 }
  ],
  "by_model": [
    { "model": "qwen2.5:7b", "calls": 1523, "tokens": 4820000 }
  ]
}
```

## ⚙️ Configuration

Copy `.env.example` to `.env` and edit:

| Variable | Description | Default |
|---|---|---|
| `WEBUI_SECRET_KEY` | JWT signing secret | auto-generated |
| `WEBUI_NAME` | Branding shown in UI | `LLM API Service` |
| `API_KEY_RATE_LIMIT` | Requests/min per key | `60` |
| `TRACKER_API_KEY` | Usage dashboard auth | auto-generated |

## 🐳 Service Management

```bash
# View all service logs
docker compose logs -f

# Restart a specific service
docker compose restart open-webui

# Stop everything
docker compose down

# Update to latest images
docker compose pull && docker compose up -d
```

## 🗂️ Project Structure

```
llm-api-gateway/
├── docker-compose.yml      # All services definition
├── deploy.sh               # One-click deploy script
├── .env.example            # Environment variables template
├── nginx/
│   ├── nginx.conf          # Reverse proxy + rate limiting
│   └── certs/              # SSL certificates (auto-generated)
├── scripts/
│   └── usage_tracker.py    # Token usage tracking service
└── examples/
    └── client_example.py   # OpenAI SDK client demo
```

## 🔧 Production Checklist

- [ ] Replace self-signed certs with Let's Encrypt (`certbot`)
- [ ] Set a strong `WEBUI_SECRET_KEY` in `.env`
- [ ] Configure firewall to restrict Ollama port (11434) to internal only
- [ ] Set up automated backups for Docker volumes
- [ ] Configure monitoring (Prometheus + Grafana recommended)

## 📄 License

MIT — see [LICENSE](LICENSE)
