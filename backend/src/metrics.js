const client = require('prom-client');

const register = new client.Registry();

// Default metrics: CPU, memory, event loop lag, GC, handles
client.collectDefaultMetrics({ register, prefix: 'jerney_' });

const httpRequestDuration = new client.Histogram({
  name: 'jerney_http_request_duration_seconds',
  help: 'Duration of HTTP requests in seconds',
  labelNames: ['method', 'route', 'status_code'],
  buckets: [0.005, 0.01, 0.05, 0.1, 0.3, 0.5, 1, 2, 5],
  registers: [register],
});

const httpRequestsTotal = new client.Counter({
  name: 'jerney_http_requests_total',
  help: 'Total number of HTTP requests',
  labelNames: ['method', 'route', 'status_code'],
  registers: [register],
});

// Normalize route to avoid high cardinality (e.g. /api/posts/123 → /api/posts/:id)
function normalizeRoute(req) {
  if (req.route) {
    const base = req.baseUrl || '';
    return base + req.route.path;
  }
  return req.path;
}

function metricsMiddleware(req, res, next) {
  const start = process.hrtime();

  res.on('finish', () => {
    const [s, ns] = process.hrtime(start);  
    const duration = s + ns / 1e9;
    const route = normalizeRoute(req);
    const labels = { method: req.method, route, status_code: res.statusCode };

    httpRequestDuration.observe(labels, duration);
    httpRequestsTotal.inc(labels);
  });

  next();
}

module.exports = { register, metricsMiddleware };
