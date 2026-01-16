# Multi-PB: Multi-Instance PocketBase Manager

## **WARNING: THIS PROJECT IS STILL IN DEVELOPMENT, AND IS NOT PRODUCTION READY**

> **Quick Start**: Run `./install.sh` to get started in minutes!
> See [DEPLOYMENT.md](DEPLOYMENT.md) for full hosting guide.
A simple, single-container solution for running multiple isolated PocketBase instances with path-based routing. No DNS setup required, minimal complexity, maximum reliability.

## Features

- **Single Container** - One Docker container, one port, hundreds of instances
- **Path-Based Routing** - Access instances via `http://host:port/{instance}/` 
- **Zero Host Conflicts** - All instances use internal ports, only one external port
- **Web Dashboard** - Beautiful UI to manage instances, view logs, and monitor status
- **Simple CLI Management** - Add/remove/start/stop instances with shell commands
- **Persistent Storage** - Single volume mount preserves all instance data
- **Automatic Routing** - Caddy reverse proxy auto-configured from manifest
- **Process Management** - Supervisord ensures all instances stay running
- **Healthchecks** - Built-in monitoring and readiness checks

## Quick Start

### 1. Install and Run

```bash
# Clone repository
git clone https://github.com/n3-rd/multi-pb.git
cd multi-pb

# Build and start
docker compose up -d
```

Multi-PB will be running on port `25983` by default.

### 2. Access the Dashboard

Open your browser and navigate to:
```
http://localhost:25983/dashboard
```

The dashboard provides a web interface to:
- View all instances and their status
- Create new instances
- Start/stop instances
- View instance logs
- Delete instances

### 3. Create Your First Instance

```bash
# Add a new PocketBase instance
docker exec multipb add-instance.sh myapp

# Access it at: http://localhost:25983/myapp/
# Or use the dashboard at: http://localhost:25983/dashboard
```

### 3. Manage Instances

```bash
# List all instances
docker exec multipb list-instances.sh

# Stop an instance
docker exec multipb stop-instance.sh myapp

# Start an instance
docker exec multipb start-instance.sh myapp

# Remove an instance
docker exec multipb remove-instance.sh myapp
```

## Installation

### Option A: Docker Compose (Recommended)

```bash
# Clone repo
git clone https://github.com/n3-rd/multi-pb.git
cd multi-pb

# Optional: Customize port in docker-compose.yml
# Default port is 25983

# Start Multi-PB
docker compose up -d

# Check status
docker ps
docker logs multipb
```

### Option B: Direct Docker

```bash
# Build image
docker build -t multipb .

# Run container
docker run -d \
  --name multipb \
  -p 25983:25983 \
  -v multipb-data:/var/multipb/data \
  multipb

# Create first instance
docker exec multipb add-instance.sh alpha
```

### Option C: Custom Port

If you want to use a different port:

```bash
# Create .env file
echo "MULTIPB_PORT=8080" > .env

# Update docker-compose.yml port mapping to match
# Then start
docker compose up -d
```

## Architecture

```
┌─────────────────────────────────────────────┐
│           Docker Container                  │
│  ┌───────────────────────────────────────┐  │
│  │  Caddy (:25983)                       │  │
│  │  - /_health  → Health check           │  │
│  │  - /_instances → List instances       │  │
│  │  - /alpha/*  → PB Instance (30000)    │  │
│  │  - /beta/*   → PB Instance (30001)    │  │
│  │  - /gamma/*  → PB Instance (30002)    │  │
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

## CLI Commands

All commands are run via `docker exec multipb <command>`:

### add-instance.sh

Create and start a new PocketBase instance.

```bash
# Basic usage
docker exec multipb add-instance.sh myapp

# With admin credentials (for future use)
docker exec multipb add-instance.sh myapp --email admin@example.com --password secret123
```

### remove-instance.sh

Stop and remove a PocketBase instance.

```bash
docker exec multipb remove-instance.sh myapp

# Will prompt to delete data directory
```

### list-instances.sh

List all configured instances.

```bash
docker exec multipb list-instances.sh

# Output:
# PocketBase Instances:
# ====================
# alpha    Port: 30000    Status: running    Created: 2024-01-13T10:30:00Z
# beta     Port: 30001    Status: running    Created: 2024-01-13T10:35:00Z
```

### start-instance.sh / stop-instance.sh

Control instance lifecycle.

```bash
# Stop an instance
docker exec multipb stop-instance.sh myapp

# Start an instance
docker exec multipb start-instance.sh myapp
```

## Configuration

### Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `MULTIPB_PORT` | `25983` | External port exposed from container |
| `MULTIPB_DATA_DIR` | `/var/multipb/data` | Data directory inside container |

Configure in `docker-compose.yml` or `.env` file.

### Port Range

Instances are assigned internal ports from `30000-39999`. This allows up to 10,000 instances per container.

### Data Persistence

All instance data is stored in a single volume:

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

For production, place Multi-PB behind your main reverse proxy (nginx, Traefik, Caddy, etc.):

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
# Traefik example (docker-compose labels)
services:
  multipb:
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.multipb.rule=Host(`pb.yourdomain.com`)"
      - "traefik.http.services.multipb.loadbalancer.server.port=25983"
```

### Subdomain Routing (Optional)

If you want subdomain-based routing instead of paths:

1. Set up wildcard DNS: `*.pb.yourdomain.com → your-server-ip`
2. Use an external reverse proxy to route subdomains to paths:

```nginx
# nginx - route subdomain to path
server {
    server_name ~^(?<instance>.+)\.pb\.yourdomain\.com$;
    location / {
        proxy_pass http://localhost:25983/$instance/;
    }
}
```

This keeps Multi-PB simple while allowing flexible routing externally.

### Backup Strategy

```bash
# Backup all data
docker run --rm \
  -v multipb-data:/data \
  -v $(pwd):/backup \
  alpine tar czf /backup/multipb-backup-$(date +%Y%m%d).tar.gz /data

# Restore data
docker run --rm \
  -v multipb-data:/data \
  -v $(pwd):/backup \
  alpine tar xzf /backup/multipb-backup-20240113.tar.gz -C /
```

### Monitoring

```bash
# Check container health
docker ps  # Should show "healthy"

# View logs
docker logs multipb

# Check instance status
docker exec multipb list-instances.sh

# Check supervisord status
docker exec multipb supervisorctl status
```

## Healthchecks

Multi-PB provides built-in healthcheck endpoints:

```bash
# Container health (used by Docker)
curl http://localhost:25983/_health

# List all instances
curl http://localhost:25983/_instances
```

## Troubleshooting

### Container won't start

```bash
# Check logs
docker logs multipb

# Verify volume
docker volume inspect multipb-data

# Check port availability
netstat -tuln | grep 25983
```

### Instance won't start

```bash
# Check instance logs
docker exec multipb cat /var/log/multipb/<instance>.log
docker exec multipb cat /var/log/multipb/<instance>.err.log

# Check supervisord status
docker exec multipb supervisorctl status

# Try restarting the instance
docker exec multipb stop-instance.sh <instance>
docker exec multipb start-instance.sh <instance>
```

### Port conflicts

Multi-PB uses internal ports (30000-39999) that don't conflict with host ports. If you still have issues:

```bash
# Check instances.json
docker exec multipb cat /var/multipb/instances.json

# Verify no port collisions
docker exec multipb netstat -tuln
```

### Can't access instance

```bash
# Verify Caddy is running
docker exec multipb supervisorctl status caddy

# Check Caddy config
docker exec multipb cat /etc/caddy/Caddyfile

# Reload proxy configuration
docker exec multipb reload-proxy.sh

# Test direct access to instance
docker exec multipb curl http://localhost:30000/api/health
```

## Development

```bash
# Clone repository
git clone https://github.com/n3-rd/multi-pb.git
cd multi-pb

# Build and run
docker compose up -d --build

# View logs
docker logs -f multipb

# Test CLI commands
docker exec multipb add-instance.sh test1
docker exec multipb list-instances.sh
docker exec multipb remove-instance.sh test1
```


## Contributing

Contributions welcome! This project prioritizes simplicity and reliability over features.

## License

MIT
