# Multi-PocketBase Docker

A single Docker container that dynamically hosts multiple isolated PocketBase instances behind Caddy with automatic SSL.

## Quick Start

```bash
# Create tenant directories
mkdir -p pb_data/app1 pb_data/app2

# Build and run
docker compose up -d --build

# Access instances (using localhost.direct for local SSL testing)
# https://app1.localhost.direct/_/
# https://app2.localhost.direct/_/
```

## How It Works

1. **Drop-in Architecture**: Add a folder to `pb_data/`, restart the container, and a new PocketBase instance is available
2. **Automatic Routing**: Folder name becomes subdomain (`myapp/` → `myapp.yourdomain.com`)
3. **Automatic SSL**: Caddy handles ACME certificates automatically
4. **Process Management**: Supervisord manages all PocketBase instances + Caddy

## Configuration

### Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `DOMAIN_NAME` | `localhost.direct` | Root domain for subdomains |
| `ACME_EMAIL` | `admin@example.com` | Email for Let's Encrypt |

### Production Example

```yaml
services:
  multi-pb:
    build: .
    ports:
      - "80:80"
      - "443:443"
    volumes:
      - /srv/pocketbase:/mnt/data
      - caddy_data:/data
      - caddy_config:/config
    environment:
      - DOMAIN_NAME=example.com
      - ACME_EMAIL=ssl@example.com
```

## Directory Structure

```
/mnt/data/
├── client-a/          → client-a.example.com
│   ├── pb_data/
│   └── pb_migrations/
├── client-b/          → client-b.example.com
│   └── ...
└── api/               → api.example.com
    └── ...
```

## Adding/Removing Tenants

```bash
# Add new tenant
mkdir pb_data/newtenant
docker compose restart

# Remove tenant (data preserved)
rm -rf pb_data/oldtenant
docker compose restart
```

## Notes

- `localhost.direct` is a public DNS that points `*.localhost.direct` to `127.0.0.1` — useful for local SSL testing
- Each PocketBase instance runs on sequential ports starting from 8081 (internal only)
- Caddy data volume persists SSL certificates across rebuilds
