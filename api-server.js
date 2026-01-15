#!/usr/bin/env node

const http = require('http');
const { exec } = require('child_process');
const { promisify } = require('util');
const execAsync = promisify(exec);
const fs = require('fs').promises;
const path = require('path');

const PORT = 3001;
const MANIFEST_FILE = '/var/multipb/instances.json';
const LOG_DIR = '/var/log/multipb';

async function execScript(script, args = []) {
	try {
		const cmd = `/usr/local/bin/${script} ${args.join(' ')}`;
		const { stdout, stderr } = await execAsync(cmd);
		return { success: true, stdout, stderr };
	} catch (error) {
		return { success: false, error: error.message, stdout: error.stdout, stderr: error.stderr };
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

async function getLogs(instanceName, lineCount = 200) {
	try {
		const logFile = path.join(LOG_DIR, `${instanceName}.log`);
		const data = await fs.readFile(logFile, 'utf8');
		const logLines = data.split('\n');
		return logLines.slice(-lineCount).join('\n');
	} catch (error) {
		return `Error reading logs: ${error.message}`;
	}
}

const server = http.createServer(async (req, res) => {
	// CORS headers
	res.setHeader('Access-Control-Allow-Origin', '*');
	res.setHeader('Access-Control-Allow-Methods', 'GET, POST, DELETE, OPTIONS');
	res.setHeader('Access-Control-Allow-Headers', 'Content-Type');

	if (req.method === 'OPTIONS') {
		res.writeHead(200);
		res.end();
		return;
	}

	const url = new URL(req.url, `http://${req.headers.host}`);
	const pathname = url.pathname;

	try {
		// GET /api/instances
		if (pathname === '/api/instances' && req.method === 'GET') {
			const manifest = await readManifest();
			const instances = Object.entries(manifest).map(([name, data]) => ({
				name,
				port: data.port,
				status: data.status || 'unknown',
				created: data.created || new Date().toISOString()
			}));

			res.writeHead(200, { 'Content-Type': 'application/json' });
			res.end(JSON.stringify({ instances }));
			return;
		}

		// POST /api/instances
		if (pathname === '/api/instances' && req.method === 'POST') {
			let body = '';
			for await (const chunk of req) {
				body += chunk;
			}
			const { name } = JSON.parse(body);

			if (!name) {
				res.writeHead(400, { 'Content-Type': 'application/json' });
				res.end(JSON.stringify({ error: 'Instance name required' }));
				return;
			}

			const result = await execScript('add-instance.sh', [name]);
			if (result.success) {
				res.writeHead(200, { 'Content-Type': 'application/json' });
				res.end(JSON.stringify({ success: true }));
			} else {
				res.writeHead(500, { 'Content-Type': 'application/json' });
				res.end(JSON.stringify({ error: result.error || result.stderr }));
			}
			return;
		}

		// DELETE /api/instances/:name
		const deleteMatch = pathname.match(/^\/api\/instances\/([^\/]+)$/);
		if (deleteMatch && req.method === 'DELETE') {
			const name = deleteMatch[1];
			const result = await execScript('remove-instance.sh', [name, '--delete-data']);
			if (result.success) {
				res.writeHead(200, { 'Content-Type': 'application/json' });
				res.end(JSON.stringify({ success: true }));
			} else {
				res.writeHead(500, { 'Content-Type': 'application/json' });
				res.end(JSON.stringify({ error: result.error || result.stderr }));
			}
			return;
		}

		// POST /api/instances/:name/start
		const startMatch = pathname.match(/^\/api\/instances\/([^\/]+)\/start$/);
		if (startMatch && req.method === 'POST') {
			const name = startMatch[1];
			const result = await execScript('start-instance.sh', [name]);
			if (result.success) {
				res.writeHead(200, { 'Content-Type': 'application/json' });
				res.end(JSON.stringify({ success: true }));
			} else {
				res.writeHead(500, { 'Content-Type': 'application/json' });
				res.end(JSON.stringify({ error: result.error || result.stderr }));
			}
			return;
		}

		// POST /api/instances/:name/stop
		const stopMatch = pathname.match(/^\/api\/instances\/([^\/]+)\/stop$/);
		if (stopMatch && req.method === 'POST') {
			const name = stopMatch[1];
			const result = await execScript('stop-instance.sh', [name]);
			if (result.success) {
				res.writeHead(200, { 'Content-Type': 'application/json' });
				res.end(JSON.stringify({ success: true }));
			} else {
				res.writeHead(500, { 'Content-Type': 'application/json' });
				res.end(JSON.stringify({ error: result.error || result.stderr }));
			}
			return;
		}

		// GET /api/instances/:name/logs
		const logsMatch = pathname.match(/^\/api\/instances\/([^\/]+)\/logs$/);
		if (logsMatch && req.method === 'GET') {
			const name = logsMatch[1];
			const logs = await getLogs(name, 200);
			res.writeHead(200, { 'Content-Type': 'application/json' });
			res.end(JSON.stringify({ logs }));
			return;
		}

		res.writeHead(404, { 'Content-Type': 'application/json' });
		res.end(JSON.stringify({ error: 'Not found' }));
	} catch (error) {
		res.writeHead(500, { 'Content-Type': 'application/json' });
		res.end(JSON.stringify({ error: error.message }));
	}
});

server.listen(PORT, '127.0.0.1', () => {
	console.log(`API server running on http://127.0.0.1:${PORT}`);
});
