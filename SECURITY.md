# Security & auth

API auth is **optional**. When you set an admin token, every request (read and write) must include it.

## 1. Set the token on the server

**Option A – environment (recommended)**

```bash
export MULTIPB_ADMIN_TOKEN="$(openssl rand -hex 24)"
# or in .env / docker-compose:
# MULTIPB_ADMIN_TOKEN=your-secret-token-here
```

**Option B – config file**

In `/var/multipb/data/config.json`:

```json
{
  "adminToken": "your-secret-token-here"
}
```

Restart or reload the API so it picks up the new token.

## 2. Use the token in requests

**curl**

```bash
TOKEN="your-secret-token-here"
BASE="http://localhost:25983/api"

# List instances
curl -s "$BASE/instances" -H "Authorization: Bearer $TOKEN"

# Create instance
curl -X POST "$BASE/instances" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"name":"myapp"}'

# Instance details, logs, backups, etc.
curl -s "$BASE/instances/myapp" -H "Authorization: Bearer $TOKEN"
curl -s "$BASE/instances/myapp/logs" -H "Authorization: Bearer $TOKEN"
```

**Dashboard**

1. Open the dashboard (e.g. `http://localhost:25983/dashboard`).
2. If the API returns 401, the “Admin token required” modal appears.
3. Otherwise use **Set token** in the sidebar.
4. Enter the same value as `MULTIPB_ADMIN_TOKEN` or `config.json` → **Unlock**.
5. The token is stored in `localStorage` and sent with every API call.

## 3. No token = open API

If you do **not** set `adminToken` or `MULTIPB_ADMIN_TOKEN`, the API allows all requests without auth. Rely on network isolation (e.g. bind to localhost only, VPN, firewall) if the port is reachable.

## 4. Generate a strong token

```bash
openssl rand -hex 24
# or
openssl rand -base64 32
```

Use one of these as `MULTIPB_ADMIN_TOKEN` or `"adminToken"` in config.
