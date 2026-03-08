'use strict';

const http = require('http');
const net = require('net');
const url = require('url');
const crypto = require('crypto');

const bridgeCore = require('./bridge_core');

// Adapter registry
const adapters = {
  feishu: require('./adapters/feishu'),
  wechat_work: require('./adapters/wechat_work'),
};

/**
 * Check if a port is already in use.
 * @param {number} port
 * @returns {Promise<boolean>} true if in use
 */
function isPortInUse(port) {
  return new Promise((resolve) => {
    const tester = net.createServer()
      .once('error', () => resolve(true))
      .once('listening', () => {
        tester.close(() => resolve(false));
      })
      .listen(port, '0.0.0.0');
  });
}

/**
 * Read full request body as Buffer.
 * @param {http.IncomingMessage} req
 * @returns {Promise<Buffer>}
 */
function readBody(req) {
  return new Promise((resolve, reject) => {
    const chunks = [];
    req.on('data', (chunk) => chunks.push(chunk));
    req.on('end', () => resolve(Buffer.concat(chunks)));
    req.on('error', reject);
  });
}

/**
 * Parse URL query string into object.
 * @param {string} queryString
 * @returns {object}
 */
function parseQuery(queryString) {
  const params = {};
  if (!queryString) return params;
  for (const part of queryString.split('&')) {
    const [k, v] = part.split('=');
    if (k) params[decodeURIComponent(k)] = decodeURIComponent(v || '');
  }
  return params;
}

/**
 * Create and return an HTTP server for the Platform Bridge.
 *
 * Routes:
 *   POST /webhook/{platform}  -> adapter.handleSpecial -> adapter.verify -> adapter.normalize -> bridge_core.route
 *   GET  /webhook/{platform}  -> adapter.handleSpecial (URL verification)
 *   GET  /health              -> 200 OK
 *
 * @param {object} config - full bridge config
 * @returns {http.Server}
 */
function createServer(config) {
  const routing = config.routing || {};
  const platforms = config.platforms || {};

  const server = http.createServer(async (req, res) => {
    const parsed = url.parse(req.url);
    const pathname = parsed.pathname || '/';
    const query = parseQuery(parsed.query);

    // Health check
    if (pathname === '/health') {
      res.writeHead(200, { 'Content-Type': 'application/json' });
      res.end(JSON.stringify({ status: 'ok', agent_id: config.agent_id }));
      return;
    }

    // Webhook route: /webhook/{platform}
    const webhookMatch = pathname.match(/^\/webhook\/([a-z_]+)$/);
    if (!webhookMatch) {
      res.writeHead(404, { 'Content-Type': 'application/json' });
      res.end(JSON.stringify({ error: 'Not found' }));
      return;
    }

    const platform = webhookMatch[1];
    const adapter = adapters[platform];
    if (!adapter) {
      res.writeHead(400, { 'Content-Type': 'application/json' });
      res.end(JSON.stringify({ error: `Unknown platform: ${platform}` }));
      return;
    }

    const platformConfig = platforms[platform] || {};
    if (!platformConfig.enabled) {
      res.writeHead(403, { 'Content-Type': 'application/json' });
      res.end(JSON.stringify({ error: `Platform ${platform} is not enabled` }));
      return;
    }

    // Read raw body
    let rawBody;
    try {
      rawBody = await readBody(req);
    } catch (err) {
      res.writeHead(400, { 'Content-Type': 'application/json' });
      res.end(JSON.stringify({ error: 'Failed to read request body' }));
      return;
    }

    // Parse body (try JSON, fall back to raw string)
    let body = null;
    try {
      body = JSON.parse(rawBody.toString('utf8'));
    } catch (e) {
      body = rawBody.toString('utf8');
    }

    // Lower-case headers
    const headers = {};
    for (const [k, v] of Object.entries(req.headers)) {
      headers[k.toLowerCase()] = v;
    }

    // handleSpecial first (URL verification, challenge, etc.)
    const handled = adapter.handleSpecial({
      body,
      query,
      method: req.method,
      res,
      config: platformConfig,
    });
    if (handled) return;

    // Verify signature
    let verified = false;
    try {
      verified = adapter.verify({ headers, rawBody, body, query }, platformConfig);
    } catch (err) {
      console.error(`[bridge] verify error on ${platform}:`, err.message);
    }
    if (!verified) {
      res.writeHead(401, { 'Content-Type': 'application/json' });
      res.end(JSON.stringify({ error: 'Signature verification failed' }));
      return;
    }

    // Normalize to AChat message
    let normalized;
    try {
      normalized = adapter.normalize(body, platformConfig, routing);
    } catch (err) {
      console.error(`[bridge] normalize error on ${platform}:`, err.message);
      res.writeHead(500, { 'Content-Type': 'application/json' });
      res.end(JSON.stringify({ error: 'Failed to normalize message' }));
      return;
    }

    // Deduplication
    const messageId = (normalized.platform_ref && normalized.platform_ref.message_id) || '';
    if (messageId && bridgeCore.isDuplicate(platform, messageId)) {
      console.log(`[bridge] Duplicate message ignored: ${platform}:${messageId}`);
      res.writeHead(200, { 'Content-Type': 'application/json' });
      res.end(JSON.stringify({ status: 'duplicate' }));
      return;
    }

    // Route to inbox
    const result = bridgeCore.route(normalized, config);

    if (result.ok) {
      console.log(`[bridge] Routed: ${platform} → ${normalized.to}`);
      res.writeHead(200, { 'Content-Type': 'application/json' });
      res.end(JSON.stringify({ status: 'ok' }));
    } else if (result.pending) {
      console.warn(`[bridge] Message pending (unauthorized): ${normalized.from} → ${normalized.to}`);
      res.writeHead(200, { 'Content-Type': 'application/json' });
      res.end(JSON.stringify({ status: 'pending' }));
    } else {
      console.error(`[bridge] Route failed:`, result.error);
      res.writeHead(500, { 'Content-Type': 'application/json' });
      res.end(JSON.stringify({ error: 'Failed to route message' }));
    }
  });

  return server;
}

/**
 * Start the bridge server.
 * Checks for port conflicts and fails fast with a friendly error.
 *
 * @param {object} config - full bridge config
 * @param {number} [portOverride] - optional port override
 * @returns {Promise<http.Server>}
 */
async function start(config, portOverride) {
  const port = portOverride || config.port || 9988;

  const inUse = await isPortInUse(port);
  if (inUse) {
    console.error(`[bridge] ERROR: Port ${port} is already in use.`);
    console.error(`[bridge] Hint: kill the process using it or use --port to specify another port.`);
    process.exit(1);
  }

  const server = createServer(config);

  return new Promise((resolve) => {
    server.listen(port, '0.0.0.0', () => {
      console.log(`[bridge] Platform Bridge listening on port ${port}`);
      console.log(`[bridge] Agent: ${config.agent_id}`);
      const platforms = Object.entries(config.platforms || {})
        .filter(([, v]) => v.enabled)
        .map(([k]) => k);
      console.log(`[bridge] Enabled platforms: ${platforms.join(', ') || 'none'}`);
      resolve(server);
    });
  });
}

module.exports = { createServer, start, isPortInUse };
