"use strict";

const express = require("express");
const helmet = require("helmet");
const rateLimit = require("express-rate-limit");

const app = express();

// Security middleware
app.use(helmet());
app.use(express.json({ limit: "10kb" }));

const globalLimiter = rateLimit({
  windowMs: 15 * 60 * 1000,
  max: 100,
  standardHeaders: true,
  legacyHeaders: false,
  message: { error: "Too many requests, please try again later." },
});
app.use(globalLimiter);

// API key auth middleware for protected endpoints
function requireApiKey(req, res, next) {
  const apiKey = process.env.ADMIN_API_KEY;
  if (!apiKey) {
    return res.status(503).json({
      error: "Protected endpoint is unavailable: ADMIN_API_KEY not configured.",
    });
  }
  const provided = req.headers["x-api-key"];
  if (!provided || provided !== apiKey) {
    return res.status(401).json({ error: "Unauthorized: invalid or missing API key." });
  }
  return next();
}

// Application state
let isHealthy = true;

// Routes
app.get("/", (req, res) => {
  res.json({
    message: "Hello from DevSecOps App",
    version: process.env.npm_package_version || "1.0.0",
    timestamp: new Date().toISOString(),
  });
});

app.get("/health", (req, res) => {
  const status = isHealthy ? "healthy" : "unhealthy";
  const code = isHealthy ? 200 : 503;
  res.status(code).json({
    status,
    uptime: process.uptime(),
    timestamp: new Date().toISOString(),
  });
});

// Protected: requires X-API-Key header
app.post("/toggle-health", requireApiKey, (req, res) => {
  const { healthy } = req.body;
  if (typeof healthy !== "boolean") {
    return res.status(400).json({
      error: "Request body must contain 'healthy' as a boolean value.",
    });
  }
  isHealthy = healthy;
  return res.json({
    updated: isHealthy,
    timestamp: new Date().toISOString(),
  });
});

// 404 handler
app.use((req, res) => {
  res.status(404).json({ error: "Route " + req.method + " " + req.path + " not found." });
});

// Global error handler — express requires 4-param signature; marked istanbul ignore
// because triggering it requires a next(err) call which is internal to Express.
/* istanbul ignore next */
app.use((err, req, res, next) => {  // eslint-disable-line no-unused-vars
  console.error("[ERROR]", err.message, err.stack);
  res.status(500).json({ error: "Internal server error." });
});

// Server factory
const server = {
  start: (port) => {
    if (
      typeof port !== "number" ||
      isNaN(port) ||
      port <= 0 ||
      port >= 65536 ||
      !Number.isInteger(port)
    ) {
      throw new Error("Invalid port number");
    }
    return new Promise((resolve) => {
      const instance = app.listen(port, () => {
        console.log("[INFO] Server running on http://localhost:" + port);
        resolve(instance);
      });
    });
  },
};

module.exports = { app, server };

// Start server when run directly — excluded from coverage (bootstrap code)
/* istanbul ignore next */
if (require.main === module) {
  const port = parseInt(process.env.PORT || "3000", 10);
  server.start(port).catch((err) => {
    console.error("[FATAL] Failed to start server:", err.message);
    process.exit(1);
  });
}
