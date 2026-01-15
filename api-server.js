#!/usr/bin/env node

const http = require('http');
const { exec, spawn } = require('child_process');
const { promisify } = require('util');
const execAsync = promisify(exec);
const fs = require('fs').promises;
const fsSync = require('fs');
const path = require('path');

const PORT = 3001;
const MANIFEST_FILE = '/var/multipb/instances.json';
const DATA_DIR = '/var/multipb/data';
const LOG_DIR = '/var/log/multipb';
const BACKUP_DIR = '/var/multipb/backups';

async function execScript(script, args = []) {
    try {
        const cmd = `/usr/local/bin/${script} ${args.join(' ')}`;
        const { stdout, stderr } = await execAsync(cmd);
        return { success: true, stdout, stderr };
    } catch (error) {
        return { success: false, error: error.message, stdout: error.stdout, stderr: error.stderr };
    }
}

async function getDirSize(directory) {
    try {
        const { stdout } = await execAsync(`du -sh "${directory}" 2>/dev/null | cut -f1`);
        return stdout.trim() || '0B';
    } catch (e) {
        return '0B';
    }
}

async function getSystemStats() {
    try {
        const { stdout: loadAvg } = await execAsync('cat /proc/loadavg 2>/dev/null || uptime | grep -oE "load average[s]?: [0-9.]+" | grep -oE "[0-9.]+"');
        const load = parseFloat(loadAvg.split(' ')[0]) || 0;
        
        let memoryPercent = 0;
        try {
            const { stdout: memInfo } = await execAsync('free -m 2>/dev/null | awk \'NR==2{printf "%.1f", $3*100/$2}\'');
            memoryPercent = parseFloat(memInfo) || 0;
        } catch (e) {}
        
        let diskUsage = '0B';
        try {
            const { stdout: du } = await execAsync(`du -sh "${DATA_DIR}" 2>/dev/null | cut -f1`);
            diskUsage = du.trim() || '0B';
        } catch (e) {}

        return { load: load.toFixed(2), memoryPercent, diskUsage };
    } catch (e) {
        return { load: null, memoryPercent: null, diskUsage: '0B' };
    }
}

async function readManifest() {
    try {
        const data = await fs.readFile(MANIFEST_FILE, 'utf8');
        return JSON.parse(data);
    } catch (error) {
        return {};
    }
}

async function writeManifest(manifest) {
    await fs.writeFile(MANIFEST_FILE, JSON.stringify(manifest, null, 2));
}

async function getLogs(instanceName, lineCount = 200) {
    try {
        const logFile = path.join(LOG_DIR, `${instanceName}.log`);
        const errFile = path.join(LOG_DIR, `${instanceName}.err.log`);
        
        let logs = '';
        try {
            const data = await fs.readFile(logFile, 'utf8');
            logs = data.split('\n').slice(-lineCount).join('\n');
        } catch (e) {}
        
        let errLogs = '';
        try {
            const data = await fs.readFile(errFile, 'utf8');
            errLogs = data.split('\n').slice(-50).join('\n');
        } catch (e) {}
        
        return { logs, errLogs };
    } catch (error) {
        return { logs: '', errLogs: `Error: ${error.message}` };
    }
}

async function getInstanceHealth(port) {
    return new Promise((resolve) => {
        const req = http.request({
            hostname: '127.0.0.1',
            port: port,
            path: '/api/health',
            method: 'GET',
            timeout: 2000
        }, (res) => {
            let data = '';
            res.on('data', chunk => data += chunk);
            res.on('end', () => {
                try {
                    resolve(JSON.parse(data));
                } catch (e) {
                    resolve(null);
                }
            });
        });
        req.on('error', () => resolve(null));
        req.on('timeout', () => { req.destroy(); resolve(null); });
        req.end();
    });
}

// Proxy request to PocketBase instance
function proxyToPocketBase(port, method, pbPath, body, authToken) {
    return new Promise((resolve, reject) => {
        const headers = { 'Content-Type': 'application/json' };
        if (authToken) headers['Authorization'] = authToken;
        if (body) headers['Content-Length'] = Buffer.byteLength(body);

        const req = http.request({
            hostname: '127.0.0.1',
            port: port,
            path: pbPath,
            method: method,
            headers,
            timeout: 30000
        }, (res) => {
            let data = '';
            res.on('data', chunk => data += chunk);
            res.on('end', () => {
                resolve({ status: res.statusCode, data, headers: res.headers });
            });
        });
        req.on('error', reject);
        req.on('timeout', () => { req.destroy(); reject(new Error('Timeout')); });
        if (body) req.write(body);
        req.end();
    });
}

// Get collections info from PocketBase
async function getCollections(port, authToken) {
    try {
        const result = await proxyToPocketBase(port, 'GET', '/api/collections', null, authToken);
        if (result.status === 200) {
            return JSON.parse(result.data);
        }
        return null;
    } catch (e) {
        return null;
    }
}

// List backups for an instance
async function listBackups(instanceName) {
    try {
        const instanceBackupDir = path.join(BACKUP_DIR, instanceName);
        try {
            await fs.access(instanceBackupDir);
        } catch {
            return [];
        }
        
        const files = await fs.readdir(instanceBackupDir);
        const backups = await Promise.all(
            files.filter(f => f.endsWith('.zip')).map(async (f) => {
                const filePath = path.join(instanceBackupDir, f);
                const stat = await fs.stat(filePath);
                return {
                    name: f,
                    size: formatBytes(stat.size),
                    created: stat.mtime.toISOString()
                };
            })
        );
        return backups.sort((a, b) => new Date(b.created) - new Date(a.created));
    } catch (e) {
        return [];
    }
}

// Create backup
async function createBackup(instanceName) {
    const instanceDir = path.join(DATA_DIR, instanceName);
    const instanceBackupDir = path.join(BACKUP_DIR, instanceName);
    
    // Ensure backup directory exists
    await fs.mkdir(instanceBackupDir, { recursive: true });
    
    const timestamp = new Date().toISOString().replace(/[:.]/g, '-');
    const backupName = `backup-${timestamp}.zip`;
    const backupPath = path.join(instanceBackupDir, backupName);
    
    try {
        // PocketBase with --dir puts files directly in instance dir (data.db, pb_migrations, etc.)
        await execAsync(`cd "${instanceDir}" && zip -r "${backupPath}" .`);
        const stat = await fs.stat(backupPath);
        return { 
            success: true, 
            backup: { 
                name: backupName, 
                size: formatBytes(stat.size), 
                created: stat.mtime.toISOString() 
            } 
        };
    } catch (e) {
        return { success: false, error: e.message };
    }
}

// Delete backup
async function deleteBackup(instanceName, backupName) {
    const backupPath = path.join(BACKUP_DIR, instanceName, backupName);
    try {
        await fs.unlink(backupPath);
        return { success: true };
    } catch (e) {
        return { success: false, error: e.message };
    }
}

// Restore backup
async function restoreBackup(instanceName, backupName) {
    const instanceDir = path.join(DATA_DIR, instanceName);
    const backupPath = path.join(BACKUP_DIR, instanceName, backupName);
    const tempBackupDir = path.join(DATA_DIR, `${instanceName}_restore_backup_${Date.now()}`);
    
    try {
        // Stop instance first
        await execScript('stop-instance.sh', [instanceName]);
        
        // Backup current data by renaming entire instance dir
        try {
            await fs.rename(instanceDir, tempBackupDir);
            await fs.mkdir(instanceDir, { recursive: true });
        } catch (e) {}
        
        // Extract backup directly to instance dir
        await execAsync(`cd "${instanceDir}" && unzip -o "${backupPath}"`);
        
        // Start instance
        await execScript('start-instance.sh', [instanceName]);
        
        // Clean up old data after successful restore
        try {
            await fs.rm(tempBackupDir, { recursive: true });
        } catch (e) {}
        
        return { success: true };
    } catch (e) {
        // Try to restore old data
        try {
            await fs.rm(instanceDir, { recursive: true });
            await fs.rename(tempBackupDir, instanceDir);
        } catch (e2) {}
        
        await execScript('start-instance.sh', [instanceName]);
        return { success: false, error: e.message };
    }
}

function formatBytes(bytes) {
    if (bytes === 0) return '0B';
    const k = 1024;
    const sizes = ['B', 'KB', 'MB', 'GB'];
    const i = Math.floor(Math.log(bytes) / Math.log(k));
    return parseFloat((bytes / Math.pow(k, i)).toFixed(1)) + sizes[i];
}

// Get instance details including collections count
async function getInstanceDetails(name, port) {
    const instanceDir = path.join(DATA_DIR, name);
    const size = await getDirSize(instanceDir);
    const health = await getInstanceHealth(port);
    
    // Count files in pb_data
    let recordsEstimate = 0;
    try {
        const dbPath = path.join(instanceDir, 'pb_data', 'data.db');
        const stat = await fs.stat(dbPath);
        recordsEstimate = Math.floor(stat.size / 1024); // rough estimate
    } catch (e) {}
    
    return {
        size,
        healthy: health !== null,
        healthData: health
    };
}

// Parse request body
async function parseBody(req) {
    let body = '';
    for await (const chunk of req) body += chunk;
    return body ? JSON.parse(body) : {};
}

const server = http.createServer(async (req, res) => {
    res.setHeader('Access-Control-Allow-Origin', '*');
    res.setHeader('Access-Control-Allow-Methods', 'GET, POST, PUT, DELETE, OPTIONS');
    res.setHeader('Access-Control-Allow-Headers', 'Content-Type, Authorization');

    if (req.method === 'OPTIONS') {
        res.writeHead(200);
        res.end();
        return;
    }

    const url = new URL(req.url, `http://${req.headers.host}`);
    const pathname = url.pathname;
    const authToken = req.headers.authorization;

    const sendJson = (status, data) => {
        res.writeHead(status, { 'Content-Type': 'application/json' });
        res.end(JSON.stringify(data));
    };

    try {
        // GET /api/stats
        if (pathname === '/api/stats' && req.method === 'GET') {
            const stats = await getSystemStats();
            return sendJson(200, stats);
        }

        // GET /api/instances
        if (pathname === '/api/instances' && req.method === 'GET') {
            const manifest = await readManifest();
            const instances = await Promise.all(Object.entries(manifest).map(async ([name, data]) => {
                const details = await getInstanceDetails(name, data.port);
                return {
                    name,
                    port: data.port,
                    status: data.status || 'unknown',
                    created: data.created || null,
                    ...details
                };
            }));
            return sendJson(200, { instances });
        }

        // GET /api/ports/check/:port - Check if port is available
        const portCheckMatch = pathname.match(/^\/api\/ports\/check\/(\d+)$/);
        if (portCheckMatch && req.method === 'GET') {
            const port = parseInt(portCheckMatch[1], 10);
            const manifest = await readManifest();
            const usedPorts = Object.values(manifest).map(i => i.port);
            const available = !usedPorts.includes(port);
            const inRange = port >= 30000 && port <= 39999;
            return sendJson(200, { 
                port, 
                available: available && inRange, 
                inRange,
                inUse: usedPorts.includes(port)
            });
        }

        // GET /api/ports/used - List all used ports
        if (pathname === '/api/ports/used' && req.method === 'GET') {
            const manifest = await readManifest();
            const usedPorts = Object.entries(manifest).map(([name, data]) => ({
                port: data.port,
                instance: name
            }));
            return sendJson(200, { ports: usedPorts, range: { min: 30000, max: 39999 } });
        }

        // POST /api/instances
        if (pathname === '/api/instances' && req.method === 'POST') {
            const { name, email, password, port } = await parseBody(req);
            if (!name) return sendJson(400, { error: 'Instance name required' });

            // Validate port if provided
            if (port !== undefined && port !== null && port !== '') {
                const portNum = parseInt(port, 10);
                if (isNaN(portNum)) {
                    return sendJson(400, { error: 'Port must be a number' });
                }
                if (portNum < 30000 || portNum > 39999) {
                    return sendJson(400, { error: 'Port must be between 30000 and 39999' });
                }
                const manifest = await readManifest();
                const usedPorts = Object.values(manifest).map(i => i.port);
                if (usedPorts.includes(portNum)) {
                    return sendJson(400, { error: `Port ${portNum} is already in use` });
                }
            }

            const args = [name];
            if (email) args.push('--email', email);
            if (password) args.push('--password', password);
            if (port) args.push('--port', port.toString());

            const result = await execScript('add-instance.sh', args);
            if (result.success) {
                return sendJson(200, { 
                    success: true, 
                    credentials: { 
                        email: email || `admin@${name}.local`, 
                        password: password || 'changeme123' 
                    }
                });
            }
            return sendJson(500, { error: result.error || result.stderr });
        }

        // GET /api/instances/:name
        const instanceMatch = pathname.match(/^\/api\/instances\/([^\/]+)$/);
        if (instanceMatch && req.method === 'GET') {
            const name = instanceMatch[1];
            const manifest = await readManifest();
            if (!manifest[name]) return sendJson(404, { error: 'Instance not found' });
            
            const data = manifest[name];
            const details = await getInstanceDetails(name, data.port);
            const backups = await listBackups(name);
            
            return sendJson(200, {
                name,
                port: data.port,
                status: data.status,
                created: data.created,
                ...details,
                backups
            });
        }

        // DELETE /api/instances/:name
        if (instanceMatch && req.method === 'DELETE') {
            const name = instanceMatch[1];
            const result = await execScript('remove-instance.sh', [name, '--delete-data']);
            if (result.success) return sendJson(200, { success: true });
            return sendJson(500, { error: result.error || result.stderr });
        }

        // POST /api/instances/:name/start
        const startMatch = pathname.match(/^\/api\/instances\/([^\/]+)\/start$/);
        if (startMatch && req.method === 'POST') {
            const name = startMatch[1];
            const result = await execScript('start-instance.sh', [name]);
            if (result.success) return sendJson(200, { success: true });
            return sendJson(500, { error: result.error || result.stderr });
        }

        // POST /api/instances/:name/stop
        const stopMatch = pathname.match(/^\/api\/instances\/([^\/]+)\/stop$/);
        if (stopMatch && req.method === 'POST') {
            const name = stopMatch[1];
            const result = await execScript('stop-instance.sh', [name]);
            if (result.success) return sendJson(200, { success: true });
            return sendJson(500, { error: result.error || result.stderr });
        }

        // POST /api/instances/:name/restart
        const restartMatch = pathname.match(/^\/api\/instances\/([^\/]+)\/restart$/);
        if (restartMatch && req.method === 'POST') {
            const name = restartMatch[1];
            await execScript('stop-instance.sh', [name]);
            const result = await execScript('start-instance.sh', [name]);
            if (result.success) return sendJson(200, { success: true });
            return sendJson(500, { error: result.error || result.stderr });
        }

        // GET /api/instances/:name/logs
        const logsMatch = pathname.match(/^\/api\/instances\/([^\/]+)\/logs$/);
        if (logsMatch && req.method === 'GET') {
            const name = logsMatch[1];
            const { logs, errLogs } = await getLogs(name, 200);
            return sendJson(200, { logs, errLogs });
        }

        // === BACKUPS ===
        
        // GET /api/instances/:name/backups
        const backupsMatch = pathname.match(/^\/api\/instances\/([^\/]+)\/backups$/);
        if (backupsMatch && req.method === 'GET') {
            const name = backupsMatch[1];
            const backups = await listBackups(name);
            return sendJson(200, { backups });
        }

        // POST /api/instances/:name/backups
        if (backupsMatch && req.method === 'POST') {
            const name = backupsMatch[1];
            const result = await createBackup(name);
            if (result.success) return sendJson(200, result);
            return sendJson(500, result);
        }

        // DELETE /api/instances/:name/backups/:backupName
        const backupDeleteMatch = pathname.match(/^\/api\/instances\/([^\/]+)\/backups\/([^\/]+)$/);
        if (backupDeleteMatch && req.method === 'DELETE') {
            const [, name, backupName] = backupDeleteMatch;
            const result = await deleteBackup(name, backupName);
            if (result.success) return sendJson(200, result);
            return sendJson(500, result);
        }

        // POST /api/instances/:name/backups/:backupName/restore
        const backupRestoreMatch = pathname.match(/^\/api\/instances\/([^\/]+)\/backups\/([^\/]+)\/restore$/);
        if (backupRestoreMatch && req.method === 'POST') {
            const [, name, backupName] = backupRestoreMatch;
            const result = await restoreBackup(name, backupName);
            if (result.success) return sendJson(200, result);
            return sendJson(500, result);
        }

        // GET /api/instances/:name/backups/:backupName/download
        const backupDownloadMatch = pathname.match(/^\/api\/instances\/([^\/]+)\/backups\/([^\/]+)\/download$/);
        if (backupDownloadMatch && req.method === 'GET') {
            const [, name, backupName] = backupDownloadMatch;
            const backupPath = path.join(BACKUP_DIR, name, backupName);
            
            try {
                const stat = await fs.stat(backupPath);
                res.writeHead(200, {
                    'Content-Type': 'application/zip',
                    'Content-Length': stat.size,
                    'Content-Disposition': `attachment; filename="${backupName}"`
                });
                fsSync.createReadStream(backupPath).pipe(res);
                return;
            } catch (e) {
                return sendJson(404, { error: 'Backup not found' });
            }
        }

        // === PROXY TO POCKETBASE ===
        
        // GET/POST/etc /api/instances/:name/pb/*
        const pbProxyMatch = pathname.match(/^\/api\/instances\/([^\/]+)\/pb(\/.*)$/);
        if (pbProxyMatch) {
            const [, name, pbPath] = pbProxyMatch;
            const manifest = await readManifest();
            if (!manifest[name]) return sendJson(404, { error: 'Instance not found' });
            
            let body = null;
            if (['POST', 'PUT', 'PATCH'].includes(req.method)) {
                body = '';
                for await (const chunk of req) body += chunk;
            }
            
            try {
                const result = await proxyToPocketBase(manifest[name].port, req.method, pbPath, body, authToken);
                res.writeHead(result.status, { 'Content-Type': result.headers['content-type'] || 'application/json' });
                res.end(result.data);
            } catch (e) {
                return sendJson(502, { error: 'Failed to connect to PocketBase: ' + e.message });
            }
            return;
        }

        sendJson(404, { error: 'Not found' });
    } catch (error) {
        sendJson(500, { error: error.message });
    }
});

server.listen(PORT, '127.0.0.1', () => {
    console.log(`API server running on http://127.0.0.1:${PORT}`);
});
