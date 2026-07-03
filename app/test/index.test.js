"use strict";

const request = require("supertest");
const { app, server } = require("../index");

const TEST_API_KEY = "test-api-key-for-jest-suite";
let appServer;

beforeAll(() => {
  process.env.ADMIN_API_KEY = TEST_API_KEY;
});

afterEach(async () => {
  if (appServer && appServer.close) {
    await new Promise((resolve) => appServer.close(resolve));
    appServer = null;
  }
});

afterAll(() => {
  delete process.env.ADMIN_API_KEY;
});

// ---------------------------------------------------------------------------
// GET /
// ---------------------------------------------------------------------------

describe("GET /", () => {
  test("responds with 200 and welcome message", async () => {
    const res = await request(app).get("/");
    expect(res.statusCode).toBe(200);
    expect(res.body.message).toContain("Hello from DevSecOps App");
  });

  test("returns JSON content-type", async () => {
    const res = await request(app).get("/");
    expect(res.headers["content-type"]).toMatch(/application\/json/);
  });

  test("includes version and timestamp fields", async () => {
    const res = await request(app).get("/");
    expect(res.body).toHaveProperty("version");
    expect(res.body).toHaveProperty("timestamp");
  });
});

// ---------------------------------------------------------------------------
// GET /health
// ---------------------------------------------------------------------------

describe("GET /health", () => {
  beforeEach(async () => {
    await request(app)
      .post("/toggle-health")
      .set("x-api-key", TEST_API_KEY)
      .send({ healthy: true });
  });

  test("returns 200 with healthy status by default", async () => {
    const res = await request(app).get("/health");
    expect(res.statusCode).toBe(200);
    expect(res.body.status).toBe("healthy");
  });

  test("returns 503 with unhealthy status after toggling off", async () => {
    await request(app)
      .post("/toggle-health")
      .set("x-api-key", TEST_API_KEY)
      .send({ healthy: false });
    const res = await request(app).get("/health");
    expect(res.statusCode).toBe(503);
    expect(res.body.status).toBe("unhealthy");
  });

  test("includes uptime and timestamp in response", async () => {
    const res = await request(app).get("/health");
    expect(res.body).toHaveProperty("uptime");
    expect(res.body).toHaveProperty("timestamp");
    expect(typeof res.body.uptime).toBe("number");
  });

  test("restores healthy state after toggling back on", async () => {
    await request(app)
      .post("/toggle-health")
      .set("x-api-key", TEST_API_KEY)
      .send({ healthy: false });
    await request(app)
      .post("/toggle-health")
      .set("x-api-key", TEST_API_KEY)
      .send({ healthy: true });
    const res = await request(app).get("/health");
    expect(res.statusCode).toBe(200);
    expect(res.body.status).toBe("healthy");
  });
});

// ---------------------------------------------------------------------------
// POST /toggle-health — authentication
// ---------------------------------------------------------------------------

describe("POST /toggle-health — authentication", () => {
  test("rejects request with no API key (401)", async () => {
    const res = await request(app)
      .post("/toggle-health")
      .send({ healthy: false });
    expect(res.statusCode).toBe(401);
    expect(res.body).toHaveProperty("error");
  });

  test("rejects request with wrong API key (401)", async () => {
    const res = await request(app)
      .post("/toggle-health")
      .set("x-api-key", "wrong-key")
      .send({ healthy: false });
    expect(res.statusCode).toBe(401);
    expect(res.body).toHaveProperty("error");
  });

  test("accepts request with correct API key (200)", async () => {
    const res = await request(app)
      .post("/toggle-health")
      .set("x-api-key", TEST_API_KEY)
      .send({ healthy: true });
    expect(res.statusCode).toBe(200);
    expect(res.body.updated).toBe(true);
  });

  test("returns 503 when ADMIN_API_KEY is not configured", async () => {
    const originalKey = process.env.ADMIN_API_KEY;
    delete process.env.ADMIN_API_KEY;
    const res = await request(app)
      .post("/toggle-health")
      .set("x-api-key", "any-key")
      .send({ healthy: false });
    expect(res.statusCode).toBe(503);
    expect(res.body).toHaveProperty("error");
    process.env.ADMIN_API_KEY = originalKey;
  });
});

// ---------------------------------------------------------------------------
// POST /toggle-health — input validation
// ---------------------------------------------------------------------------

describe("POST /toggle-health — input validation", () => {
  test("rejects non-boolean healthy value — string (400)", async () => {
    const res = await request(app)
      .post("/toggle-health")
      .set("x-api-key", TEST_API_KEY)
      .send({ healthy: "true" });
    expect(res.statusCode).toBe(400);
    expect(res.body).toHaveProperty("error");
  });

  test("rejects non-boolean healthy value — number (400)", async () => {
    const res = await request(app)
      .post("/toggle-health")
      .set("x-api-key", TEST_API_KEY)
      .send({ healthy: 1 });
    expect(res.statusCode).toBe(400);
  });

  test("rejects missing healthy field (400)", async () => {
    const res = await request(app)
      .post("/toggle-health")
      .set("x-api-key", TEST_API_KEY)
      .send({});
    expect(res.statusCode).toBe(400);
  });

  test("accepts false as a valid boolean toggle (200)", async () => {
    const res = await request(app)
      .post("/toggle-health")
      .set("x-api-key", TEST_API_KEY)
      .send({ healthy: false });
    expect(res.statusCode).toBe(200);
    expect(res.body.updated).toBe(false);
    await request(app)
      .post("/toggle-health")
      .set("x-api-key", TEST_API_KEY)
      .send({ healthy: true });
  });

  test("response includes timestamp", async () => {
    const res = await request(app)
      .post("/toggle-health")
      .set("x-api-key", TEST_API_KEY)
      .send({ healthy: true });
    expect(res.body).toHaveProperty("timestamp");
  });
});

// ---------------------------------------------------------------------------
// Security headers (helmet)
// ---------------------------------------------------------------------------

describe("Security headers", () => {
  test("sets X-Content-Type-Options header", async () => {
    const res = await request(app).get("/");
    expect(res.headers["x-content-type-options"]).toBe("nosniff");
  });

  test("sets X-Frame-Options header", async () => {
    const res = await request(app).get("/");
    expect(res.headers["x-frame-options"]).toBeDefined();
  });

  test("does not expose X-Powered-By header", async () => {
    const res = await request(app).get("/");
    expect(res.headers["x-powered-by"]).toBeUndefined();
  });

  test("sets Content-Security-Policy header", async () => {
    const res = await request(app).get("/");
    expect(res.headers["content-security-policy"]).toBeDefined();
  });
});

// ---------------------------------------------------------------------------
// 404 handler
// ---------------------------------------------------------------------------

describe("404 handler", () => {
  test("returns 404 for unknown GET route", async () => {
    const res = await request(app).get("/nonexistent");
    expect(res.statusCode).toBe(404);
    expect(res.body).toHaveProperty("error");
  });

  test("returns 404 for unknown POST route", async () => {
    const res = await request(app).post("/unknown");
    expect(res.statusCode).toBe(404);
  });
});

// ---------------------------------------------------------------------------
// Server lifecycle
// ---------------------------------------------------------------------------

describe("Server lifecycle", () => {
  test("starts successfully on a valid port", async () => {
    appServer = await server.start(4001);
    expect(appServer.listening).toBe(true);
  });

  test.each([
    ["string", "abc"],
    ["negative", -1],
    ["zero", 0],
    ["too high", 70000],
    ["float", 3.14],
    ["null", null],
    ["undefined", undefined],
    ["object", {}],
    ["array", []],
  ])("throws for invalid port — %s (%p)", (_label, invalidPort) => {
    expect(() => server.start(invalidPort)).toThrow("Invalid port number");
  });

  test("resolves with a server instance that has a .close method", async () => {
    appServer = await server.start(4002);
    expect(typeof appServer.close).toBe("function");
  });
});
