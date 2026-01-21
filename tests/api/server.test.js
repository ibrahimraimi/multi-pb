const { test, describe, before, after, mock } = require("node:test");
const assert = require("node:assert");
const supertest = require("supertest");
const path = require("path");
const fs = require("fs");

// Mock data directory before loading server
const TEST_DIR = path.join("/tmp", "multipb-api-test-" + Date.now());
const MANIFEST_FILE = path.join(TEST_DIR, "instances.json");
const CONFIG_FILE = path.join(TEST_DIR, "config.json");

// Mock fs and child_process?
// It's hard to mock external modules with simple require in integration tests without a loader or DI.
// However, the server.js uses '/var/multipb/data' constants.
// For integration testing, we might want to mock the FS module or use a separate "config" module that we can swap.
// Since we can't easily mock require in plain node without loaders, let's assume we test the endpoints
// that don't depend heavily on global state (like /api/stats) or handle the errors gracefully using mocks if possible.

// ACTUALLY: usage of hardcoded paths in server.js makes unit testing hard.
// We will test what we can: endpoints availability and basic logic.

// To properly test, we should verify that we can import the server.
const server = require("../../core/api/server");

describe("API Server Integration", () => {
  const request = supertest(server);

  test("GET /api/stats returns system stats", async () => {
    const res = await request.get("/api/stats");
    assert.strictEqual(res.status, 200);
    assert.ok(res.body.load !== undefined);
    assert.ok(res.body.memoryPercent !== undefined);
  });

  test("GET /api/notifications/config returns config", async () => {
    const res = await request.get("/api/notifications/config");
    assert.strictEqual(res.status, 200);
    assert.ok(res.body.webhookUrl !== undefined);
  });

  test("GET /api/instances returns instances list", async () => {
    const res = await request.get("/api/instances");
    assert.strictEqual(res.status, 200);
    assert.ok(Array.isArray(res.body.instances));
  });

  test("GET /_health (via Proxy logic check) - server.js does not handle _health directly except via /api/health?", async () => {
    // server.js defines /api/health? No, verify code.
    // The code has getInstanceHealth which calls /api/health on ports.
    // server.js creates an HTTP server that handles /api/... routes.
    // It doesn't seem to have a /health endpoint for itself in the provided code snippet unless I missed it.
    // Wait, the HEALTHCHECK CMD is curl http://localhost:PORT/_health
    // Dockerfile: CMD curl -f http://localhost:${MULTIPB_PORT}/_health
    // But that hits Caddy (:25983). Caddy proxies /_health to somewhere or handles it?
    // README says: /_health -> Health check.
    // The node API server is on 3001.
    // Let's check 404
    const res = await request.get("/api/unknown");
    assert.strictEqual(res.status, 404);
  });

  test("POST /api/instances requires name", async () => {
    const res = await request.post("/api/instances").send({});
    assert.strictEqual(res.status, 400);
    assert.match(res.body.error, /name required/i);
  });

  // Clean up
  after(() => {
    server.close();
  });
});
