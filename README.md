# Multi-PB: Multi-Instance PocketBase Manager

> **WARNING: THIS PROJECT IS STILL IN DEVELOPMENT AND NOT PRODUCTION READY.**

A single-container solution for running multiple isolated PocketBase instances with path-based routing.

## Features

- **Single Container**: Run hundreds of instances on a single port.
- **Path-Based Routing**: Auto-configured Caddy proxy (e.g., `domain.com/myapp/_/`).
- **Resource Control**: Set memory limits per instance.
- **Monitoring**: Background health checks with Discord/Slack notifications.
- **Management**: Web Dashboard and CLI tools.
- **Backups**: Built-in backup/restore and import tools.

## Project Structure

This project follows a monorepo-style structure:

```
├── apps/
│   ├── dashboard/   # SvelteKit Dashboard
│   ├── docs/        # Documentation
│   └── web/         # Landing Page (Future)
├── core/
│   ├── api/         # Node.js API Server
│   ├── cli/         # Shell Scripts (add-instance, etc.)
│   └── entrypoint.sh
├── Dockerfile       # Main container build
└── install.sh       # Installer script
```

See the [Development Guide](apps/docs/DEVELOPMENT.md) for more details on project structure and testing.

## Quick Start

```bash
git clone https://github.com/n3-rd/multi-pb.git
cd multi-pb
./install.sh
```

Access dashboard at: `http://localhost:25983/dashboard`

## Security: Setting an Admin Token

By default, the API is open to anyone who can reach it. To secure it, set an admin token:

**Option 1: Environment variable (recommended)**
```bash
export MULTIPB_ADMIN_TOKEN="$(openssl rand -hex 24)"
# Or add to docker-compose.yml:
# environment:
#   - MULTIPB_ADMIN_TOKEN=your-secret-token-here
```
**Important:** Restart the container/server for the environment variable to take effect.

**Option 2: Instant CLI (No restart required)**
To instantly set or change the token without restarting:
```bash
docker exec multipb set-admin-token.sh "your-secret-token-here"
```
This updates `config.json` immediately. To remove the token, pass an empty string:
```bash
docker exec multipb set-admin-token.sh ""
```

**Option 3: Config file**
Edit `/var/multipb/data/config.json`:
```json
{
  "adminToken": "your-secret-token-here"
}
```
The API server watches this file and will reload the token instantly.
**Note:** The token in `config.json` takes precedence over the environment variable.

**Using the token in the dashboard:**
1. Open `http://localhost:25983/dashboard`
2. If the server requires a token, you'll see an **"Admin token required"** modal before accessing the dashboard
3. Enter your token and click **"Unlock"**
4. You can also click **"Set token"** in the sidebar anytime to change it

The token is stored in your browser and sent with every API request. See [SECURITY.md](SECURITY.md) for more details and curl examples.

## Documentation

- [**Installation Guide**](docs/INSTALLATION.md) - Docker Compose, Installer options, Deployment.
- [**CLI Reference**](docs/CLI.md) - Command line tools for managing instances.
- [**API Reference**](docs/API.md) - HTTP API endpoints.
- [**Configuration**](docs/CONFIGURATION.md) - Notifications, Webhooks, Resource Limits.

## Architecture

Multi-PB uses a Supervisord process manager to run multiple PocketBase binaries alongside a Caddy reverse proxy and a Node.js API server for management.

```
[ Docker Container ]
  ├── Caddy (Reverse Proxy & Routing)
  ├── Node.js API (Management & Monitoring)
  └── Supervisord
      ├── PocketBase Instance 1
      ├── PocketBase Instance 2
      └── ...
```

## License

MIT
