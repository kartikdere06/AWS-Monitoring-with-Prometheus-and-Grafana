# AWS Monitoring with Prometheus and Grafana

A ready-to-run monitoring stack for Linux/EC2 hosts. **Prometheus** scrapes CPU, memory, disk and system metrics from `node_exporter`, **Grafana** shows them on a pre-built dashboard, and **Alertmanager** handles alerts that surface infrastructure problems early.

## Architecture

```
  EC2 host A          EC2 host B          Monitoring host (EC2)
 ┌───────────┐       ┌───────────┐       ┌───────────────────────────────┐
 │ node_     │       │ node_     │       │  Prometheus ──► Alertmanager  │
 │ exporter  │◄──────┤ exporter  │◄──────┤      ▲                        │
 │  :9100    │ scrape│  :9100    │ scrape│      │ query                  │
 └───────────┘       └───────────┘       │  Grafana (dashboards) :3000   │
                                         └───────────────────────────────┘
```

- `node_exporter` runs as a systemd service on every host to be monitored.
- Prometheus, Alertmanager and Grafana run in Docker Compose on one monitoring host.
- Grafana's data source and dashboard are **provisioned from files**, so there is nothing to click through after startup.

## What is monitored

| Area | Metrics |
|------|---------|
| CPU | utilisation per instance, load average |
| Memory | used % based on `MemAvailable` |
| Disk | used % per mount point, read/write throughput, 24h fill prediction |
| Network | receive/transmit bytes per interface |
| Availability | scrape `up` status per host |

## Alerts

Defined in [`prometheus/alerts.yml`](prometheus/alerts.yml):

| Alert | Condition | Severity |
|-------|-----------|----------|
| InstanceDown | Host not scrapeable for 2 min | critical |
| HighCpuUsage | CPU > 80% for 5 min | warning |
| HighMemoryUsage | Memory > 85% for 5 min | warning |
| DiskSpaceLow | Filesystem > 85% for 10 min | warning |
| DiskSpaceCritical | Filesystem > 95% for 5 min | critical |
| DiskWillFillIn24h | Linear prediction hits zero within 24h | warning |
| HighLoadAverage | 5-min load > 2x cores for 10 min | warning |

By default, alerts are visible in Prometheus (`:9090/alerts`), Alertmanager (`:9093`) and Grafana. To get notified, configure a receiver (email/SES or Slack examples are in [`alertmanager/alertmanager.yml`](alertmanager/alertmanager.yml)).

## Repository layout

```
.
├── docker-compose.yml
├── .env.example
├── prometheus/
│   ├── prometheus.yml        # scrape config (file-based + optional EC2 discovery)
│   ├── alerts.yml            # alert rules
│   └── targets/node.yml      # list of hosts to scrape
├── alertmanager/
│   └── alertmanager.yml
├── grafana/
│   ├── provisioning/         # data source + dashboard provider
│   └── dashboards/node-overview.json
└── scripts/
    ├── setup-monitoring-host.sh   # Docker + Compose on the monitoring host
    └── install-node-exporter.sh   # node_exporter as a systemd service
```

## Setup

### 1. Launch EC2 instances

- **Monitoring host:** t3.small or larger, Amazon Linux 2023 or Ubuntu
- **Targets:** any Linux instances (they can include the monitoring host)

### 2. Security groups

| Port | Source | Purpose |
|------|--------|---------|
| 3000 | Your IP | Grafana UI |
| 9090, 9093 | Your IP (optional) | Prometheus / Alertmanager UI |
| 9100 | Monitoring host's security group | node_exporter scrape |
| 22 | Your IP | SSH |

Do not open 9100 to the internet.

### 3. Install node_exporter on every target

```bash
sudo bash scripts/install-node-exporter.sh
```

### 4. Start the stack on the monitoring host

```bash
bash scripts/setup-monitoring-host.sh     # first time only; log out/in afterwards
cp .env.example .env                       # set GRAFANA_ADMIN_PASSWORD
docker compose up -d
```

### 5. Add your hosts

Edit `prometheus/targets/node.yml` and list each instance's private IP with port 9100. Prometheus re-reads the file every minute, so no restart is needed.

For larger fleets, use the commented `ec2_sd_configs` block in `prometheus/prometheus.yml`. It discovers instances by tag (`Monitoring=true`) and needs an IAM role with `ec2:DescribeInstances` on the monitoring host.

### 6. Open Grafana

`http://<monitoring-host-public-ip>:3000`, log in with the credentials from `.env`, then open **Dashboards -> Infrastructure -> EC2 Node Overview**.

Check that targets are healthy at `http://<host>:9090/targets`.

## Testing the alerts

Generate CPU load on a monitored host and watch the alert move from Pending to Firing:

```bash
sudo dnf install -y stress-ng      # or: sudo apt-get install -y stress-ng
stress-ng --cpu 0 --timeout 600s
```

Then check `http://<host>:9090/alerts`. To test `InstanceDown`, stop the exporter: `sudo systemctl stop node_exporter`.

## Operations

```bash
docker compose logs -f prometheus      # troubleshoot scraping
docker compose restart prometheus      # after editing prometheus.yml or alerts.yml
curl -X POST localhost:9090/-/reload   # reload config without restart
docker compose pull && docker compose up -d   # upgrade (bump pinned versions first)
```

Prometheus keeps 15 days of data (`--storage.tsdb.retention.time` in `docker-compose.yml`). Put the Docker volumes on an EBS volume sized for your retention needs.

## Security notes

- Grafana sign-up is disabled and the admin password comes from `.env` (git-ignored).
- Put Grafana behind HTTPS (ALB with ACM certificate or nginx) before exposing it beyond your IP.
- Prometheus and Alertmanager have no authentication. Keep ports 9090/9093 closed to the internet.

## Ideas for improvement

- Add CloudWatch exporter or `yet-another-cloudwatch-exporter` for managed services (RDS, ALB)
- Add `blackbox_exporter` for HTTP/TLS endpoint checks
- Run Prometheus with remote write to long-term storage
- Provision the monitoring host with Terraform

## License

MIT
