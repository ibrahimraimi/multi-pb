# Installation Guide

## Quick Start

The fastest way to get started is using the installer script:

```bash
git clone https://github.com/n3-rd/multi-pb.git
cd multi-pb
./install.sh
```

### Installer Options

- `--cli-only`: Skip building the dashboard (useful for minimal setups)
- `--port <port>`: Specify a custom external port (default: 25983)
- `--non-interactive`: Skip all prompts (uses defaults)
- `--domain <domain>`: Enable HTTPS support with Caddy

## Docker Compose

You can also run directly with Docker Compose:

```bash
docker compose up -d
```

To configure, edit `.env` or `docker-compose.yml`:

- `MULTIPB_PORT`: External access port
- `MULTIPB_DATA_DIR`: Where data is stored inside the container
- `MULTIPB_DOMAIN`: If set, Caddy will obtain SSL certificates

## Production Deployment

### Behind Nginx

```nginx
server {
    listen 80;
    server_name pb.yourdomain.com;

    location / {
        proxy_pass http://localhost:25983;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
}
```

### Subdomain Routing

Multi-PB uses path-based routing (`/instance-name/`). To map subdomains (`instance.domain.com`), you need a wildcard DNS record and a reverse proxy configuration:

```nginx
server {
    server_name ~^(?<instance>.+)\.pb\.yourdomain\.com$;
    location / {
        proxy_pass http://localhost:25983/$instance/;
    }
}
```
