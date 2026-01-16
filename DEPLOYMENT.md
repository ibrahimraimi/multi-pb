# Deployment Guide

This guide covers how to host **Multi-PB** in various environments.

## Hosting Recommendations

Since Multi-PB relies on persistent processes (Caddy, API Server, PocketBase) and local SQLite databases, it runs best on a **VPS (Virtual Private Server)**.

### ✅ Recommended: VPS
- **Providers**: [Hetzner](https://hetzner.com) (Best Value), [DigitalOcean](https://digitalocean.com), [Linode](https://linode.com).
- **OS**: Ubuntu 22.04 LTS or Debian 12.
- **Specs**:
    - **CPU**: 2+ vCPUs recommended (PocketBase is efficient, but multiple instances add up).
    - **RAM**: 2GB+ (API Server + Caddy + ~20MB per idle PocketBase instance).
    - **Storage**: SSD/NVMe required for SQLite performance.

### ⚠️ Alternative: PaaS with Persistent Storage
Platform-as-a-Service providers can work **IF** they support persistent disks and long-running Docker containers.
- **[Coolify](https://coolify.io)**: Excellent self-hosted PaaS. Fits perfectly.
- **CapRover**: Another solid self-hosted option.
- **Railway/Render**: Possible, but you MUST attach a persistent volume to `/var/multipb/data` or you will lose all data on restart.

### ⛔ Not Recommended
- **Serverless (Vercel, Netlify, Cloudflare Workers)**: This application requires long-running background processes and cannot run on serverless functions.
- **Heroku (Standard)**: Ephemeral filesystem means you will lose data every 24 hours.

---

## Installation Steps

### 1. Provision Server
SSH into your fresh Ubuntu/Debian server:
```bash
ssh root@your-server-ip
```

### 2. Install Docker
If Docker is not installed, run:
```bash
curl -fsSL https://get.docker.com | sh
```

### 3. Deploy Multi-PB
Clone the repository and run the installer:

```bash
git clone https://github.com/n3-rd/multi-pb.git
cd multi-pb
./install.sh
```

Follow the prompts to set your desired port (default: `25983`).

### 4. DNS Setup (Optional)
To use a real domain (e.g., `pb.example.com`):
1. Point your domain's **A Record** to your server IP.
2. Update the `Caddyfile` or put a reverse proxy (like Nginx or another Caddy instance) in front of Multi-PB to handle SSL termination for the main dashboard.

---

## Automated / Unattended Install
For automation tools (Ansible, Terraform, User Scripts), use the non-interactive mode:

```bash
./install.sh --non-interactive \
    --port 8080 \
    --data-dir /opt/multipb-data \
    --name multipb-production
```
