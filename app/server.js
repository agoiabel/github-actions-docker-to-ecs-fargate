const http = require('http');
const PORT = process.env.PORT || 3000;

const server = http.createServer((req, res) => {
  /**
   * /health — container liveness check.
   *
   * Rules:
   *   1. Always returns 200 as long as the Node process is alive.
   *   2. Never calls a database, cache, or any external service.
   *   3. Kept as fast and cheap as possible — it runs every 30 seconds.
   *
   * If this endpoint calls an external dependency and that dependency
   * has a brief outage, ECS will kill every running task and replace them
   * with new ones that also fail — leaving you with zero tasks serving traffic.
   */
  if (req.url === '/health') {
    res.writeHead(200, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify({ status: 'ok' }));
    return;
  }

  res.writeHead(200, { 'Content-Type': 'application/json' });
  res.end(JSON.stringify({
    message: 'Hello from ECS Fargate!',
    environment: process.env.APP_ENV || 'unknown',
    commit: process.env.GIT_COMMIT || 'unknown',
  }));
});

server.listen(PORT, () => console.log(`Listening on port ${PORT}`));