# ── Stage 1: deps ─────────────────────────────────────────────────────────────
# Install only production dependencies.
# Keeping this in a separate stage means npm and its cache never
# make it into the final image — smaller image, smaller attack surface.
FROM node:20-alpine AS deps
WORKDIR /app
COPY package.json ./
RUN npm install --omit=dev

# ── Stage 2: runtime ──────────────────────────────────────────────────────────
# Copy only what the app needs to run. No build tools. No npm.
FROM node:20-alpine AS runtime
WORKDIR /app

# Always run containers as a non-root user.
# If an attacker breaks out of the app they land as appuser, not root.
RUN addgroup -S appgroup && adduser -S appuser -G appgroup
USER appuser

COPY --from=deps /app/node_modules ./node_modules
COPY . .

# CI passes the exact commit SHA at build time.
# The running container exposes it at /health or in API responses
# so you can confirm which code is deployed without guessing.
ARG GIT_COMMIT=unknown
ENV GIT_COMMIT=${GIT_COMMIT}

EXPOSE 3000
CMD ["node", "server.js"]