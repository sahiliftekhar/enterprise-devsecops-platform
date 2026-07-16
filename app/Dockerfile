# =============================================================================
# Stage 1 — Dependencies
# Install only production dependencies in an isolated layer so the final image
# never contains devDependencies (test frameworks, linters, etc.)
# =============================================================================
FROM node:20-alpine AS deps

WORKDIR /usr/src/app

# Install dumb-init for proper PID-1 / signal handling
RUN apk add --no-cache dumb-init

# Copy manifests and install production deps with a clean, reproducible install.
# Do NOT run 'npm audit fix --force' here: --force can silently break semver
# contracts and introduce regressions. Audit and remediate vulnerabilities in
# your CI pipeline (npm audit --audit-level=moderate) before this build.
COPY package.json package-lock.json ./
RUN npm ci --omit --ignore-scripts

# =============================================================================
# Stage 2 — Runtime image
# Copy only what the app needs to run — no dev tools, no package sources.
# =============================================================================
FROM node:20-alpine AS runtime

LABEL maintainer="Iftekhar Shahil"
LABEL org.opencontainers.image.title="Enterprise DevSecOps Platform"
LABEL org.opencontainers.image.description="Secure Node.js Application"
LABEL org.opencontainers.image.version="1.0.0"
LABEL org.opencontainers.image.source="https://github.com/sahiliftekhar/enterprise-devsecops-platform"

# Create a least-privilege non-root user before anything else
RUN addgroup -g 1001 -S nodejs && \
    adduser  -S nodejs -u 1001 -G nodejs

WORKDIR /usr/src/app

# Pull dumb-init binary from the deps stage (avoids re-installing)
COPY --from=deps /usr/bin/dumb-init /usr/bin/dumb-init

# Copy installed node_modules from deps stage
COPY --from=deps /usr/src/app/node_modules ./node_modules

# Copy application source — ownership set to nodejs in one layer
COPY --chown=nodejs:nodejs . .

# Drop to non-root user
USER nodejs

# Expose application port
EXPOSE 3000

# Health check — test the actual HTTP /health endpoint, not just 'node --version'
# --start-period gives Node.js time to initialise before the first probe fires.
HEALTHCHECK --interval=30s --timeout=5s --start-period=15s --retries=3 \
    CMD wget -qO- http://localhost:3000/health | grep -q '"status":"healthy"' || exit 1

# dumb-init is PID 1 so SIGTERM is forwarded correctly to the Node process
ENTRYPOINT ["dumb-init", "--"]

CMD ["node", "index.js"]
