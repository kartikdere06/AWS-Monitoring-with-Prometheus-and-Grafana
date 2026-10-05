#!/usr/bin/env bash
# Installs node_exporter as a systemd service on a Linux host (Amazon Linux,
# Ubuntu, etc.). Run this on EVERY EC2 instance you want to monitor, including
# the host that runs Prometheus/Grafana.
#
# Usage: sudo bash install-node-exporter.sh [version]

set -euo pipefail

VERSION="${1:-1.8.2}"

case "$(uname -m)" in
  x86_64)  ARCH=amd64 ;;
  aarch64) ARCH=arm64 ;;
  *) echo "Unsupported architecture: $(uname -m)" >&2; exit 1 ;;
esac

if [ "$(id -u)" -ne 0 ]; then
  echo "Run as root: sudo bash $0" >&2
  exit 1
fi

TARBALL="node_exporter-${VERSION}.linux-${ARCH}.tar.gz"
URL="https://github.com/prometheus/node_exporter/releases/download/v${VERSION}/${TARBALL}"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

echo "==> Downloading node_exporter ${VERSION} (${ARCH})"
curl -fsSL "$URL" -o "$TMP/$TARBALL"
tar -xzf "$TMP/$TARBALL" -C "$TMP"
install -m 0755 "$TMP/node_exporter-${VERSION}.linux-${ARCH}/node_exporter" /usr/local/bin/node_exporter

id node_exporter >/dev/null 2>&1 || useradd --system --no-create-home --shell /usr/sbin/nologin node_exporter

cat > /etc/systemd/system/node_exporter.service <<'UNIT'
[Unit]
Description=Prometheus Node Exporter
After=network-online.target
Wants=network-online.target

[Service]
User=node_exporter
Group=node_exporter
Type=simple
ExecStart=/usr/local/bin/node_exporter --collector.systemd --collector.processes
Restart=on-failure

[Install]
WantedBy=multi-user.target
UNIT

systemctl daemon-reload
systemctl enable --now node_exporter

sleep 1
if curl -fsS http://127.0.0.1:9100/metrics | head -n 3 >/dev/null; then
  echo "==> node_exporter is running on :9100"
else
  echo "!! node_exporter did not respond; check: journalctl -u node_exporter" >&2
  exit 1
fi

echo "Security group reminder: allow 9100/tcp ONLY from the Prometheus server."
