# Multi-PB

A multi-tenant PocketBase management platform. Run multiple isolated PocketBase instances behind a single reverse proxy with automatic SSL.

## Quick Start

### Install on VPS

```bash
curl -fsSL https://raw.githubusercontent.com/your-repo/multi-pb/main/install.sh | bash
```

Or clone and run locally:

```bash
git clone https://github.com/your-repo/multi-pb.git
cd multi-pb
./install.sh
```

### What happens:
1. **Prompts for configuration** (domain, port, data directory)
2. **Creates docker-compose.yml** with your settings
3. **Starts the container**
4. **Opens the dashboard** for onboarding

## Features

- **Dynamic tenant management** - Create/delete PocketBase instances via dashboard
- **Automatic routing** - Each tenant gets a subdomain (`myapp.yourdomain.com`)
- **Hot reload** - No container restart needed when adding tenants
- **Flexible deployment** - Works behind any reverse proxy or standalone
- **Web dashboard** - Modern UI for managing instances

## Architecture

```
┌─────────────────────────────────────────────┐
│                Your VPS                     │
│  ┌───────────────────────────────────────┐  │
│  │    Your Reverse Proxy (optional)      │  │
│  │    (Traefik, nginx, Caddy, etc.)      │  │
│  └──────────────────┬────────────────────┘  │
│                     │                       │
│  ┌──────────────────▼────────────────────┐  │
│  │         Multi-PB Container            │  │
│  │  ┌─────────────────────────────────┐  │  │
│  │  │           Caddy                 │  │  │
│  │  │   (internal routing + SSL)      │  │  │
│  │  └──────────────┬──────────────────┘  │  │
│  │                 │                     │  │
│  │  ┌──────┬───────┴───────┬──────┐     │  │
│  │  │      │               │      │     │  │
│  │  ▼      ▼               ▼      ▼     │  │
│  │ Dashboard  PB-1      PB-2    PB-N    │  │
│  │ :3000     :8081     :8082   :808N    │  │
│  └───────────────────────────────────────┘  │
└─────────────────────────────────────────────┘
```

## Configuration

### Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `DOMAIN_NAME` | `localhost.direct` | Base domain for subdomains |
| `HTTP_PORT` | `8080` | Internal HTTP port |
| `HTTPS_PORT` | `8443` | Internal HTTPS port (if enabled) |
| `ENABLE_HTTPS` | `false` | Enable ACME SSL certificates |
| `ACME_EMAIL` | `admin@example.com` | Email for Let's Encrypt |
| `DATA_DIR` | `/mnt/data` | Data directory path |

### Deployment Options

#### Option A: Behind existing reverse proxy (recommended)

Your proxy (Traefik, nginx, Caddy, etc.) handles SSL and routes `*.pb.yourdomain.com` to Multi-PB.

```yaml
ports:
  - "127.0.0.1:8080:8080"  # Only accessible locally
environment:
  - DOMAIN_NAME=pb.yourdomain.com
  - ENABLE_HTTPS=false     # Proxy handles SSL
```

#### Option B: Standalone with SSL

Multi-PB handles SSL directly (no external proxy needed).

```yaml
ports:
  - "80:8080"
  - "443:8443"
environment:
  - DOMAIN_NAME=yourdomain.com
  - ENABLE_HTTPS=true
  - ACME_EMAIL=ssl@yourdomain.com
```

## Usage

### Dashboard

Access the dashboard at:
- Local: `http://localhost:8080`
- Production: `https://dashboard.yourdomain.com`

### Create a tenant

1. Click "New Instance" in dashboard
2. Enter subdomain (e.g., `myapp`)
3. Click "Create"

The instance is immediately available at `https://myapp.yourdomain.com/_/`

### API

```bash
# Get status
curl http://localhost:8080/api/status

# List tenants
curl http://localhost:8080/api/tenants

# Create tenant
curl -X POST http://localhost:8080/api/tenants \
  -H "Content-Type: application/json" \
  -d '{"subdomain": "myapp", "name": "My App"}'

# Delete tenant
curl -X DELETE http://localhost:8080/api/tenants/myapp

# Restart tenant
curl -X POST http://localhost:8080/api/tenants/myapp/restart
```

## Development

```bash
# Clone
git clone https://github.com/your-repo/multi-pb.git
cd multi-pb

# Build and run
docker compose up -d --build

# View logs
docker logs -f multi-pb

# Access dashboard
open http://localhost:8080
```

### Project Structure

```
multi-pb/
├── cmd/multipb/          # Go management server
├── internal/
│   ├── api/              # HTTP API handlers
│   ├── config/           # Configuration store
│   ├── manager/          # Process manager
│   └── models/           # Data models
├── multi-frontend/       # SvelteKit dashboard
├── Dockerfile            # Multi-stage build
├── docker-compose.yml    # Development config
├── install.sh            # Installation script
└── README.md
```

## DNS Setup

For production, configure wildcard DNS:

```
*.pb.yourdomain.com  A  <your-vps-ip>
```

Or if using the root domain:

```
*.yourdomain.com  A  <your-vps-ip>
```

## License

MIT
