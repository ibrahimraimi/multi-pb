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
