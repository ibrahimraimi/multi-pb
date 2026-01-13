# Production Deployment Guide

## Overview

Multi-PB is designed for simple, reliable production deployments. This guide covers best practices for running Multi-PB in production environments.

## Production-Ready Features

✅ **Single Port Exposure** - Only one configurable port exposed (default 25983)  
✅ **Internal Port Management** - No host-level port conflicts  
✅ **Path-Based Routing** - No DNS requirements for basic functionality  
✅ **Process Supervision** - Automatic restart of failed instances  
✅ **Health Monitoring** - Built-in healthcheck endpoints  
✅ **Log Rotation** - Automatic log management (10MB max, 3 backups)  
✅ **Persistent Storage** - Single volume mount for all data  
✅ **Minimal Dependencies** - Alpine-based, < 100MB image  

## Quick Production Deployment

### 1. Basic Production Setup

```bash
# Create production directory
mkdir -p /srv/multipb
cd /srv/multipb

# Create docker-compose.yml
cat > docker-compose.yml << 'EOF'
services:
  multipb:
    image: ghcr.io/n3-rd/multi-pb:latest
    container_name: multipb
    restart: unless-stopped
    ports:
      - "25983:25983"
    volumes:
      - /srv/multipb/data:/var/multipb/data
    environment:
      - MULTIPB_PORT=25983
      - MULTIPB_DATA_DIR=/var/multipb/data
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:25983/_health"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period=15s
    deploy:
      resources:
        limits:
          cpus: '4'
          memory: 4G
        reservations:
          cpus: '1'
          memory: 512M
EOF

# Start Multi-PB
docker compose up -d

# Create first instance
docker exec multipb add-instance.sh production
```

### 2. Behind Reverse Proxy (Recommended)

For production, place Multi-PB behind a reverse proxy for SSL termination and additional security.

#### nginx

```nginx
# /etc/nginx/sites-available/multipb
server {
    listen 80;
    server_name pb.yourdomain.com;
    
    # Redirect to HTTPS
    return 301 https://$server_name$request_uri;
}

server {
    listen 443 ssl http2;
    server_name pb.yourdomain.com;
    
    ssl_certificate /etc/letsencrypt/live/pb.yourdomain.com/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/pb.yourdomain.com/privkey.pem;
    
    # Security headers
    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header X-Content-Type-Options "nosniff" always;
    add_header X-XSS-Protection "1; mode=block" always;
    
    location / {
        proxy_pass http://127.0.0.1:25983;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        
        # WebSocket support for PocketBase realtime
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
    }
}
```

Then:
```bash
sudo ln -s /etc/nginx/sites-available/multipb /etc/nginx/sites-enabled/
sudo nginx -t
sudo systemctl reload nginx
```

#### Caddy

```caddyfile
# /etc/caddy/Caddyfile
pb.yourdomain.com {
    reverse_proxy localhost:25983
}
```

#### Traefik (Docker)

```yaml
# Add to docker-compose.yml
services:
  multipb:
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.multipb.rule=Host(`pb.yourdomain.com`)"
      - "traefik.http.routers.multipb.entrypoints=websecure"
      - "traefik.http.routers.multipb.tls.certresolver=letsencrypt"
      - "traefik.http.services.multipb.loadbalancer.server.port=25983"
    # Remove ports section when using Traefik
```

### 3. Subdomain Routing (Optional)

If you prefer subdomain-based access (e.g., `myapp.pb.yourdomain.com` instead of `pb.yourdomain.com/myapp/`):

1. **Set up wildcard DNS:**
   ```
   *.pb.yourdomain.com  A  <your-server-ip>
   ```

2. **Configure reverse proxy to route subdomains to paths:**

   ```nginx
   # nginx - subdomain to path routing
   server {
       listen 443 ssl http2;
       server_name ~^(?<instance>.+)\.pb\.yourdomain\.com$;
       
       ssl_certificate /etc/letsencrypt/live/pb.yourdomain.com/fullchain.pem;
       ssl_certificate_key /etc/letsencrypt/live/pb.yourdomain.com/privkey.pem;
       
       location / {
           proxy_pass http://127.0.0.1:25983/$instance/;
           proxy_set_header Host $host;
           # ... other proxy headers
       }
   }
   ```

## Security Checklist

- [ ] **Firewall Configuration**
  ```bash
  # Allow only SSH, HTTP, and HTTPS
  sudo ufw allow 22/tcp
  sudo ufw allow 80/tcp
  sudo ufw allow 443/tcp
  sudo ufw enable
  
  # Multi-PB port should NOT be exposed directly
  # Access only through reverse proxy
  ```

- [ ] **Bind Multi-PB to localhost only**
  ```yaml
  # docker-compose.yml
  ports:
    - "127.0.0.1:25983:25983"  # Only accessible from localhost
  ```

- [ ] **Set proper file permissions**
  ```bash
  sudo chown -R 1000:1000 /srv/multipb/data
  sudo chmod 755 /srv/multipb/data
  ```

- [ ] **Enable automatic security updates**
  ```bash
  sudo apt install unattended-upgrades
  sudo dpkg-reconfigure -plow unattended-upgrades
  ```

- [ ] **Configure log monitoring** (see Monitoring section below)

- [ ] **Set up automated backups** (see Backup Strategy below)

## Backup Strategy

### Automated Daily Backups

```bash
# Create backup script
cat > /usr/local/bin/backup-multipb.sh << 'EOF'
#!/bin/bash
BACKUP_DIR="/srv/backups/multipb"
DATE=$(date +%Y%m%d-%H%M%S)
mkdir -p "$BACKUP_DIR"

# Backup data directory
tar czf "$BACKUP_DIR/multipb-data-$DATE.tar.gz" -C /srv/multipb/data .

# Keep only last 7 days
find "$BACKUP_DIR" -name "multipb-data-*.tar.gz" -mtime +7 -delete

echo "Backup completed: multipb-data-$DATE.tar.gz"
EOF

chmod +x /usr/local/bin/backup-multipb.sh

# Add to crontab (daily at 2 AM)
(crontab -l 2>/dev/null; echo "0 2 * * * /usr/local/bin/backup-multipb.sh >> /var/log/multipb-backup.log 2>&1") | crontab -
```

### Manual Backup

```bash
# Create backup
docker run --rm \
  -v multipb-data:/data \
  -v /srv/backups:/backup \
  alpine tar czf /backup/multipb-$(date +%Y%m%d).tar.gz -C /data .

# Verify backup
tar tzf /srv/backups/multipb-$(date +%Y%m%d).tar.gz | head
```

### Restore from Backup

```bash
# Stop Multi-PB
docker compose down

# Restore data
docker run --rm \
  -v multipb-data:/data \
  -v /srv/backups:/backup \
  alpine sh -c "rm -rf /data/* && tar xzf /backup/multipb-20240113.tar.gz -C /data"

# Start Multi-PB
docker compose up -d
```

## Monitoring

### Container Health

```bash
# Check container status
docker ps  # Should show "healthy"

# View container logs
docker logs multipb --tail 100 -f

# Check resource usage
docker stats multipb
```

### Instance Health

```bash
# List all instances
docker exec multipb list-instances.sh

# Check supervisord status
docker exec multipb supervisorctl status

# View instance logs
docker exec multipb cat /var/log/multipb/<instance>.log
docker exec multipb tail -f /var/log/multipb/<instance>.log
```

### Healthcheck Endpoints

```bash
# Container health
curl http://localhost:25983/_health

# List instances
curl http://localhost:25983/_instances
```

### Prometheus Monitoring (Optional)

Use cAdvisor or docker metrics exporter:

```yaml
# Add to docker-compose.yml
services:
  cadvisor:
    image: gcr.io/cadvisor/cadvisor:latest
    container_name: cadvisor
    ports:
      - "8080:8080"
    volumes:
      - /:/rootfs:ro
      - /var/run:/var/run:ro
      - /sys:/sys:ro
      - /var/lib/docker/:/var/lib/docker:ro
```

## Performance Tuning

### Resource Limits

Adjust based on your workload:

```yaml
# docker-compose.yml
deploy:
  resources:
    limits:
      cpus: '8'      # Max CPUs
      memory: 8G     # Max memory
    reservations:
      cpus: '2'      # Minimum guaranteed
      memory: 1G
```

### Instance Limits

Multi-PB supports up to 10,000 instances (ports 30000-39999). For optimal performance:

- **1-10 instances**: Default settings work well
- **10-50 instances**: Increase memory limit to 4GB
- **50-100 instances**: Consider 8GB memory, 4 CPUs
- **100+ instances**: Monitor resource usage, consider horizontal scaling

### Horizontal Scaling

For very large deployments:

1. Run multiple Multi-PB containers on different ports
2. Use external load balancer to distribute
3. Each container manages its own set of instances

```yaml
# Container 1: Ports 25983 (instances A-M)
# Container 2: Ports 25984 (instances N-Z)
```

## Troubleshooting

### High Memory Usage

```bash
# Check top processes
docker exec multipb top

# Check individual instance memory
docker exec multipb ps aux | grep pocketbase

# Adjust container memory limit if needed
# Edit docker-compose.yml and restart
```

### Disk Space Issues

```bash
# Check disk usage
df -h /srv/multipb/data

# Check instance sizes
docker exec multipb du -sh /var/multipb/data/*

# Clean up logs
docker exec multipb find /var/log/multipb -name "*.log" -mtime +30 -delete
```

### Instance Won't Start

```bash
# Check instance logs
docker exec multipb cat /var/log/multipb/<instance>.err.log

# Check supervisord status
docker exec multipb supervisorctl status pb-<instance>

# Try manual start with debug
docker exec multipb /usr/local/bin/pocketbase serve \
  --dir=/var/multipb/data/<instance> \
  --http=127.0.0.1:30000
```

### Port Exhaustion

```bash
# Check how many ports are used
docker exec multipb cat /var/multipb/instances.json | grep -o '"port"' | wc -l

# If approaching 10,000 instances, consider:
# 1. Cleaning up unused instances
# 2. Deploying additional Multi-PB containers
# 3. Increasing port range (requires code modification)
```

## Maintenance

### Update Multi-PB

```bash
# Pull latest image
docker compose pull

# Recreate container
docker compose up -d

# Verify
docker ps
docker exec multipb list-instances.sh
```

### Clean Up Logs

```bash
# Rotate logs manually
docker exec multipb find /var/log/multipb -name "*.log" -mtime +7 -delete

# Or use logrotate
cat > /etc/logrotate.d/multipb << 'EOF'
/srv/multipb/data/.multi-pb/logs/*.log {
    daily
    rotate 7
    compress
    delaycompress
    notifempty
    create 0644 root root
}
EOF
```

### Database Maintenance

Each PocketBase instance manages its own SQLite database. For maintenance:

```bash
# Vacuum database (reduce size, optimize)
docker exec multipb sqlite3 /var/multipb/data/<instance>/pb_data/data.db "VACUUM;"

# Check database integrity
docker exec multipb sqlite3 /var/multipb/data/<instance>/pb_data/data.db "PRAGMA integrity_check;"
```

## Migration from Old Version

If migrating from the subdomain-based Multi-PB:

1. **Export instance data** from old deployment
2. **Deploy new simplified Multi-PB**
3. **For each old instance:**
   ```bash
   # Create new instance
   docker exec multipb add-instance.sh <name>
   
   # Stop the new instance
   docker exec multipb stop-instance.sh <name>
   
   # Copy data from old instance
   docker cp old-container:/mnt/data/<instance> /srv/multipb/data/<instance>
   
   # Restart instance
   docker exec multipb start-instance.sh <name>
   ```

## Support

For issues or questions:
- GitHub Issues: https://github.com/n3-rd/multi-pb/issues
- Documentation: https://github.com/n3-rd/multi-pb

## License

MIT
