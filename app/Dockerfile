FROM node:20-alpine
WORKDIR /app

# Always run containers as a non-root user.
# If an attacker breaks out of the app they land as appuser, not root.
RUN addgroup -S appgroup && adduser -S appuser -G appgroup
USER appuser

COPY . .

# CI passes the exact commit SHA at build time.
# The running container exposes it at /health or in API responses
# so you can confirm which code is deployed without guessing.
ARG GIT_COMMIT=unknown
ENV GIT_COMMIT=${GIT_COMMIT}

EXPOSE 3000
CMD ["node", "server.js"]