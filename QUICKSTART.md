# Multi-PB Quick Start Guide

This guide will get you up and running with Multi-PB in under 5 minutes.

## Prerequisites

- Docker and Docker Compose installed
- A server or local machine with at least 512MB RAM
- Port 25983 available (or any port you prefer)

## Installation

### Method 1: Using install.sh (Recommended)

```bash
# Clone the repository
git clone https://github.com/n3-rd/multi-pb.git
cd multi-pb

# Run the installer
./install.sh

# Follow the prompts:
# - External port: 25983 (default)
# - Data directory: ./multipb-data (default)
# - Container name: multipb (default)
# - Start now? Y

# Wait for startup...
# Multi-PB is now running!
```

### Method 2: Manual Docker Compose

```bash
# Clone the repository
git clone https://github.com/n3-rd/multi-pb.git
cd multi-pb

# Start Multi-PB
docker compose up -d

# Check status
docker ps
docker logs multipb
```

## First Instance

Create your first PocketBase instance:

```bash
# Create instance named "myapp"
docker exec multipb add-instance.sh myapp

# Output:
# Adding instance: myapp
# Instance 'myapp' added with port 30000
# Data directory: /var/multipb/data/myapp
# ...
# ✓ Instance 'myapp' is ready!
#   Access at: http://<host>:25983/myapp/
```

Access it at: `http://localhost:25983/myapp/_/`

## Managing Instances

### List all instances

```bash
docker exec multipb list-instances.sh
```

Output:
```
PocketBase Instances:
====================
myapp  Port: 30000  Status: running  Created: 2024-01-13T10:30:00Z

Total: 1
```

### Create more instances

```bash
# Create "blog" instance
docker exec multipb add-instance.sh blog

# Create "api" instance
docker exec multipb add-instance.sh api

# List them
docker exec multipb list-instances.sh
```

Output:
```
PocketBase Instances:
====================
api    Port: 30001  Status: running  Created: 2024-01-13T10:35:00Z
blog   Port: 30002  Status: running  Created: 2024-01-13T10:32:00Z
myapp  Port: 30000  Status: running  Created: 2024-01-13T10:30:00Z

Total: 3
```

### Stop an instance

```bash
docker exec multipb stop-instance.sh blog
# ✓ Instance 'blog' stopped
```

### Start an instance

```bash
docker exec multipb start-instance.sh blog
# ✓ Instance 'blog' started
```

### Remove an instance

```bash
docker exec multipb remove-instance.sh api

# Output:
# Removing instance: api
# Instance stopped via supervisord
# Removed supervisord config
# Removed from manifest
# Delete data directory? (y/N): n
# Data directory preserved: /var/multipb/data/api
# ✓ Instance 'api' removed
```

## Accessing Instances

Each instance is accessible at a path-based URL:

- Main: `http://localhost:25983/`
- Instance: `http://localhost:25983/{instance}/`
- Admin UI: `http://localhost:25983/{instance}/_/`
- API: `http://localhost:25983/{instance}/api/`

Examples:
```bash
# Health check
curl http://localhost:25983/_health

# List instances
curl http://localhost:25983/_instances

# Access myapp admin
open http://localhost:25983/myapp/_/

# Access myapp API
curl http://localhost:25983/myapp/api/health
```

## Setting Up Your First Instance

1. **Access the admin UI:**
   ```
   http://localhost:25983/myapp/_/
   ```

2. **Create admin account:**
   - Email: `admin@example.com`
   - Password: `YourSecurePassword123`

3. **Create your first collection:**
   - Click "Collections"
   - Click "New collection"
   - Choose "Base" type
   - Name: `posts`
   - Add fields as needed

4. **Use the API:**
   ```bash
   # List collections
   curl http://localhost:25983/myapp/api/collections
   
   # Create a record (after auth)
   curl -X POST http://localhost:25983/myapp/api/collections/posts/records \
     -H "Content-Type: application/json" \
     -d '{"title": "My first post", "content": "Hello world"}'
   ```

## Production Deployment

### Behind a Reverse Proxy

For production, place Multi-PB behind nginx/Caddy/Traefik:

**nginx example:**
```nginx
server {
    listen 80;
    server_name pb.yourdomain.com;
    
    location / {
        proxy_pass http://localhost:25983;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        
        # WebSocket support
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
    }
}
```

**Caddy example:**
```caddyfile
pb.yourdomain.com {
    reverse_proxy localhost:25983
}
```

### Backup Your Data

```bash
# Backup all instances
docker run --rm \
  -v multipb_multipb-data:/data \
  -v $(pwd):/backup \
  alpine tar czf /backup/multipb-backup-$(date +%Y%m%d).tar.gz -C /data .

# Restore
docker run --rm \
  -v multipb_multipb-data:/data \
  -v $(pwd):/backup \
  alpine tar xzf /backup/multipb-backup-20240113.tar.gz -C /data
```

### Monitor Health

```bash
# Container health
docker ps
docker logs multipb

# Instance status
docker exec multipb list-instances.sh

# Supervisor status
docker exec multipb supervisorctl status
```

## Common Tasks

### Restart Multi-PB

```bash
docker restart multipb
```

All instances will be restored automatically.

### View Instance Logs

```bash
# View real-time logs
docker exec multipb tail -f /var/log/multipb/myapp.log

# View error logs
docker exec multipb tail -f /var/log/multipb/myapp.err.log
```

### Change External Port

Edit `docker-compose.yml`:
```yaml
ports:
  - "8080:25983"  # Change 8080 to your preferred port
```

Then restart:
```bash
docker compose down
docker compose up -d
```

### Access Inside Container

```bash
# Get a shell
docker exec -it multipb sh

# Check manifest
cat /var/multipb/instances.json

# Check Caddy config
cat /etc/caddy/Caddyfile

# Check supervisor status
supervisorctl status
```

## Troubleshooting

### Container won't start

```bash
# Check logs
docker logs multipb

# Check port availability
netstat -tuln | grep 25983

# Verify volume
docker volume inspect multipb_multipb-data
```

### Instance won't start

```bash
# Check instance logs
docker exec multipb cat /var/log/multipb/<instance>.err.log

# Check supervisor status
docker exec multipb supervisorctl status pb-<instance>

# Try restarting
docker exec multipb stop-instance.sh <instance>
docker exec multipb start-instance.sh <instance>
```

### Can't access instance

```bash
# Test health endpoint
curl http://localhost:25983/_health

# Verify instance is listed
curl http://localhost:25983/_instances

# Check Caddy is running
docker exec multipb supervisorctl status caddy

# Reload proxy config
docker exec multipb reload-proxy.sh
```

## Next Steps

- Read the [full README](README.md) for more details
- Check [PRODUCTION.md](PRODUCTION.md) for production best practices
- Explore [PocketBase documentation](https://pocketbase.io/docs/)

## Getting Help

- GitHub Issues: https://github.com/n3-rd/multi-pb/issues
- PocketBase Discord: https://discord.gg/pocketbase

## Summary

You now have:
- ✅ Multi-PB running in a single container
- ✅ Multiple PocketBase instances on one port
- ✅ Path-based routing configured
- ✅ CLI tools for instance management
- ✅ Persistent data storage

Enjoy building with Multi-PB! 🚀
