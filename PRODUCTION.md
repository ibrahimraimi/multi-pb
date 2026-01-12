# Production Deployment Guide

## Production-Ready Features

✅ **Tenant Name Sanitization** - Special characters in folder names are sanitized for safe config generation  
✅ **Port Exhaustion Protection** - Fails fast if too many instances (>65k)  
✅ **Log Rotation** - 10MB logs with 3 backups (prevents disk fill)  
✅ **Security Headers** - X-Content-Type-Options, X-Frame-Options, X-XSS-Protection, Referrer-Policy  
✅ **Resource Limits** - CPU/memory limits in docker-compose  
✅ **Health Checks** - Container health monitoring via supervisorctl  
✅ **Caddy Data Persistence** - SSL certs persist across restarts  

## Production docker-compose.yml

```yaml
services:
  multi-pb:
    build: .
    container_name: multi-pb
    restart: unless-stopped
    ports:
      - "80:80"
      - "443:443"
    volumes:
      - /srv/pocketbase:/mnt/data  # Use absolute path
      - caddy_data:/data
      - caddy_config:/config
    environment:
      - DOMAIN_NAME=example.com
      - ACME_EMAIL=ssl@example.com
      # LOCAL_DEV not set = real Let's Encrypt certs
    deploy:
      resources:
        limits:
          cpus: '2'
          memory: 2G
        reservations:
          cpus: '0.5'
          memory: 512M
    healthcheck:
      test: ["CMD", "supervisorctl", "status"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 40s

volumes:
  caddy_data:
  caddy_config:
```

## DNS Setup

Before deploying, ensure DNS is configured:

```bash
# Wildcard DNS record
*.example.com  A  <your-vps-ip>
```

## Security Checklist

- [ ] Use strong ACME_EMAIL (real email for cert expiration notices)
- [ ] Set proper file permissions on `/srv/pocketbase` (chmod 755)
- [ ] Configure firewall (ufw/iptables) to allow only 80/443
- [ ] Use non-root user for data directory if possible
- [ ] Enable automatic security updates on VPS
- [ ] Set up log monitoring/rotation on host
- [ ] Configure backups for `/srv/pocketbase`

## Monitoring

```bash
# Check container health
docker ps  # Should show "healthy"

# View logs
docker logs multi-pb

# Check supervisor status
docker exec multi-pb supervisorctl status

# Monitor resource usage
docker stats multi-pb
```

## Backup Strategy

```bash
# Backup all PocketBase instances
tar -czf pb-backup-$(date +%Y%m%d).tar.gz /srv/pocketbase

# Backup Caddy SSL certs
docker run --rm -v multi-pb_caddy_data:/data -v $(pwd):/backup alpine tar czf /backup/caddy-data-$(date +%Y%m%d).tar.gz /data
```

## Troubleshooting

**Container exits immediately:**
- Check logs: `docker logs multi-pb`
- Verify tenant directories exist in `/mnt/data`
- Check port conflicts

**SSL certs not renewing:**
- Verify DNS points to your VPS
- Check Caddy logs: `docker exec multi-pb cat /var/log/supervisor/caddy.err.log`
- Ensure ports 80/443 are accessible

**High memory usage:**
- Adjust `deploy.resources.limits.memory` in docker-compose.yml
- Monitor with `docker stats`
