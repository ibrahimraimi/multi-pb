# Multi-PB: Multi-Instance PocketBase Manager

## **WARNING: THIS PROJECT IS STILL IN DEVELOPMENT, NOT PRODUCTION READY,AND STILL RECEIVES CONSTANT BREAKING UPDATES**

> **Quick Start**: Run `./install.sh` to get started in minutes!
> See [DEPLOYMENT.md](DEPLOYMENT.md) for full hosting guide.

A single-container solution for running multiple isolated PocketBase instances with path-based routing. No DNS setup required.

## Features

- **Single Container** - One Docker container, one port, hundreds of instances
- **Path-Based Routing** - Access instances via `http://host:port/{instance}/_/`
- **Web Dashboard** - UI to manage instances, view logs, and monitor status
- **CLI Management** - Add/remove/start/stop instances with shell commands
- **Auto-Routing** - Caddy reverse proxy auto-configured from manifest

## Quick Start

```bash
# Clone and install
git clone https://github.com/n3-rd/multi-pb.git
cd multi-pb
./install.sh

# Or use docker compose directly
docker compose up -d

# Create your first instance
docker exec multipb add-instance.sh myapp

# Access at: http://localhost:25983/myapp/_/
# Dashboard: http://localhost:25983/dashboard
```

## Installation Options

### Installer Script (Recommended)

```bash
./install.sh                    # Full installation
./install.sh --cli-only         # Skip dashboard build
./install.sh --port 8080         # Custom port
./install.sh --non-interactive   # No prompts
```

### Docker Compose

```bash
docker compose up -d
```

### Direct Docker

```bash
docker build -t multipb .
docker run -d --name multipb -p 25983:25983 -v multipb-data:/var/multipb/data multipb
```

## CLI Commands

All commands run via `docker exec multipb <command>`:

### add-instance.sh

Create and start a new PocketBase instance.

```bash
docker exec multipb add-instance.sh myapp
docker exec multipb add-instance.sh myapp --email admin@example.com --password secret123
```

### list-instances.sh

List all configured instances with status.

```bash
docker exec multipb list-instances.sh
```

### start-instance.sh / stop-instance.sh

Control instance lifecycle.

```bash
docker exec multipb stop-instance.sh myapp
docker exec multipb start-instance.sh myapp
```

### remove-instance.sh

Stop and remove a PocketBase instance.

```bash
docker exec multipb remove-instance.sh myapp
```

### reload-proxy.sh

Regenerate Caddy configuration from manifest.

```bash
docker exec multipb reload-proxy.sh
```

### backup-instance.sh

Create a backup of a PocketBase instance.

```bash
docker exec multipb backup-instance.sh myapp
```

Backups are stored in `/var/multipb/backups/<instance-name>/` as timestamped ZIP files.

### list-backups.sh

List backups for an instance or all instances.

```bash
# List backups for a specific instance
docker exec multipb list-backups.sh myapp

# List backups for all instances
docker exec multipb list-backups.sh
```

### restore-instance.sh

Restore a PocketBase instance from a backup.

```bash
docker exec multipb restore-instance.sh myapp backup-2024-01-15T10-30-00Z.zip
```

The instance will be stopped, restored, and restarted automatically. Current data is backed up before restoration.

### view-logs.sh

View logs for a PocketBase instance.

```bash
# View last 50 lines of stdout log
docker exec multipb view-logs.sh myapp

# View error log
docker exec multipb view-logs.sh myapp --stderr

# View last 100 lines
docker exec multipb view-logs.sh myapp --tail 100

# Follow log output (like tail -f)
docker exec multipb view-logs.sh myapp --follow
```

## Architecture

```
┌─────────────────────────────────────────────┐
│           Docker Container                  │
│  ┌───────────────────────────────────────┐  │
│  │  Caddy (:25983)                       │  │
│  │  - /_health  → Health check           │  │
│  │  - /_instances → List instances       │  │
│  │  - /{instance}/* → PB Instance        │  │
│  └──────────────┬────────────────────────┘  │
│                 │                           │
│    ┌────────────┴──────────────┐            │
│    │     Supervisord            │            │
│    │  (Process Manager)         │            │
│    └────────────┬──────────────┘            │
│                 │                           │
│  ┌──────┬───────┴───────┬──────┐            │
│  │      │               │      │            │
│  ▼      ▼               ▼      ▼            │
│ PB-1  PB-2   ...      PB-N                  │
│:30000 :30001          :30N                  │
└─────────────────────────────────────────────┘
         ▲
         │
    One Port: 25983
```

## Configuration

### Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `MULTIPB_PORT` | `25983` | External port exposed from container |
| `MULTIPB_DATA_DIR` | `/var/multipb/data` | Data directory inside container |

### Port Range

Instances are assigned internal ports from `30000-39999` (up to 10,000 instances).

### Data Structure

```
/var/multipb/data/
├── alpha/          # Instance "alpha" data
│   ├── pb_data/
│   └── pb_migrations/
├── beta/           # Instance "beta" data
└── instances.json  # Manifest mapping instances to ports
```

## Production Deployment

### Behind a Reverse Proxy

```nginx
# nginx example
server {
    listen 80;
    server_name pb.yourdomain.com;
    location / {
        proxy_pass http://localhost:25983;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
    }
}
```

```yaml
# Traefik example
services:
  multipb:
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.multipb.rule=Host(`pb.yourdomain.com`)"
      - "traefik.http.services.multipb.loadbalancer.server.port=25983"
```

### Subdomain Routing

Set up wildcard DNS (`*.pb.yourdomain.com`) and route subdomains to paths:

```nginx
server {
    server_name ~^(?<instance>.+)\.pb\.yourdomain\.com$;
    location / {
        proxy_pass http://localhost:25983/$instance/;
    }
}
```

### Backup

```bash
# Backup all data
docker run --rm -v multipb-data:/data -v $(pwd):/backup \
  alpine tar czf /backup/multipb-backup-$(date +%Y%m%d).tar.gz /data

# Restore
docker run --rm -v multipb-data:/data -v $(pwd):/backup \
  alpine tar xzf /backup/multipb-backup-20240113.tar.gz -C /
```

## Healthchecks

```bash
# Container health
curl http://localhost:25983/_health

# List all instances
curl http://localhost:25983/_instances
```

## Monitoring

```bash
# Check container health
docker ps

# View logs
docker logs multipb

# Check instance status
docker exec multipb list-instances.sh

# Check supervisord status
docker exec multipb supervisorctl status
```

## Troubleshooting

### Container won't start

```bash
docker logs multipb
docker volume inspect multipb-data
netstat -tuln | grep 25983
```

### Instance won't start

```bash
# Check logs
docker exec multipb cat /var/log/multipb/<instance>.log
docker exec multipb cat /var/log/multipb/<instance>.err.log

# Check status
docker exec multipb supervisorctl status

# Restart instance
docker exec multipb stop-instance.sh <instance>
docker exec multipb start-instance.sh <instance>
```

### Can't access instance

```bash
# Verify Caddy
docker exec multipb supervisorctl status caddy

# Check config
docker exec multipb cat /etc/caddy/Caddyfile

# Reload proxy
docker exec multipb reload-proxy.sh

# Test direct access
docker exec multipb curl http://localhost:30000/api/health
```

## Development

```bash
git clone https://github.com/n3-rd/multi-pb.git
cd multi-pb
docker compose up -d --build
docker logs -f multipb

# Test commands
docker exec multipb add-instance.sh test1
docker exec multipb list-instances.sh
docker exec multipb remove-instance.sh test1
```

### Testing

```bash
# Test installation
./test-install.sh

# Test all CLI functionality
./test-cli.sh [container-name]

# Example: Test against a specific container
./test-cli.sh multipb
```

The `test-cli.sh` script tests all CLI commands including:
- Instance management (add, list, start, stop, remove)
- Backup operations (backup, list, restore)
- Log viewing
- Error handling
- Command options and flags


## Contributing

Contributions welcome! This project prioritizes simplicity and reliability over features.

## License

MIT
