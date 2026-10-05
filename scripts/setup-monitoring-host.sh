#!/usr/bin/env bash
# Prepares the EC2 instance that will run Prometheus + Grafana + Alertmanager.
# Supports Amazon Linux 2023 and Ubuntu. Installs Docker and the Compose plugin.
#
# Usage: bash setup-monitoring-host.sh

set -euo pipefail

if command -v dnf >/dev/null 2>&1; then
  sudo dnf install -y docker
  sudo systemctl enable --now docker
  # Compose v2 plugin
  sudo mkdir -p /usr/local/lib/docker/cli-plugins
  sudo curl -fsSL "https://github.com/docker/compose/releases/download/v2.29.7/docker-compose-linux-$(uname -m)" \
    -o /usr/local/lib/docker/cli-plugins/docker-compose
  sudo chmod +x /usr/local/lib/docker/cli-plugins/docker-compose
elif command -v apt-get >/dev/null 2>&1; then
  sudo apt-get update -y
  sudo apt-get install -y docker.io docker-compose-v2
  sudo systemctl enable --now docker
else
  echo "Unsupported OS: need dnf or apt-get" >&2
  exit 1
fi

sudo usermod -aG docker "$USER"

echo
echo "Docker installed. Log out and back in, then:"
echo "  cp .env.example .env && nano .env     # set GRAFANA_ADMIN_PASSWORD"
echo "  sudo bash scripts/install-node-exporter.sh"
echo "  docker compose up -d"
