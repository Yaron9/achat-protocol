'use strict';

const crypto = require('crypto');
const https = require('https');

// Module-level token cache
let _tokenCache = null;
let _tokenExpireAt = 0;

/**
 * Verify webhook signature from Feishu.
 * Feishu signature = HMAC-SHA256(timestamp + nonce + rawBody, verification_token)
 * Also checks timestamp within 5 minutes to prevent replay.
 *
 * @param {object} opts
 * @param {object} opts.headers - HTTP headers (lowercase keys)
 * @param {Buffer|string} opts.rawBody - raw request body bytes
 * @param {object} opts.body - parsed JSON body
 * @param {object} config - platform config (verification_token)
 * @returns {boolean}
 */
function verify({ headers, rawBody, body }, config) {
  const token = config.verification_token || '';

  // If no token configured, skip verification (dev mode)
  if (!token) return true;

  const timestamp = headers['x-lark-request-timestamp'] || '';
  const nonce = headers['x-lark-request-nonce'] || '';
  const signature = headers['x-lark-signature'] || '';

  // Replay attack prevention: timestamp must be within 5 minutes
  const now = Math.floor(Date.now() / 1000);
  const ts = parseInt(timestamp, 10);
  if (isNaN(ts) || Math.abs(now - ts) > 300) {
    return false;
  }

  // Compute expected signature
  const rawBodyStr = Buffer.isBuffer(rawBody) ? rawBody.toString('utf8') : (rawBody || '');
  const payload = timestamp + nonce + rawBodyStr;
  const expected = crypto.createHmac('sha256', token).update(payload).digest('hex');

  // Use constant-time comparison to prevent timing attacks
  if (!signature || signature.length !== expected.length) return false;
  try {
    return crypto.timingSafeEqual(Buffer.from(expected), Buffer.from(signature));
  } catch (e) {
    return expected === signature;
  }
}

/**
 * Handle special Feishu events (URL verification challenge).
 * Returns true if handled (caller should stop processing).
 *
 * @param {object} opts
 * @param {object} opts.body - parsed body
 * @param {object} opts.query - URL query params
 * @param {object} opts.res - HTTP response object
 * @returns {boolean}
 */
function handleSpecial({ body, query, res }) {
  if (body && body.type === 'url_verification') {
    const resp = JSON.stringify({ challenge: body.challenge });
    res.writeHead(200, { 'Content-Type': 'application/json' });
    res.end(resp);
    return true;
  }
  return false;
}

/**
 * Normalize a Feishu event payload into NormalizedAchatMessage.
 *
 * Feishu event structure:
 *   body.event.message.content  -> JSON string with { text: "..." }
 *   body.event.message.chat_id  -> "oc_xxx"
 *   body.event.message.message_id -> "om_xxx"
 *   body.event.sender.sender_id.open_id -> "ou_xxx"
 *
 * @param {object} payload - parsed Feishu event body
 * @param {object} config - platform config
 * @param {object} routingConfig - routing table {chat_id -> agent_id}
 * @returns {object} NormalizedAchatMessage
 */
function normalize(payload, config, routingConfig) {
  const event = (payload.event) || {};
  const message = event.message || {};
  const sender = event.sender || {};

  const chatId = message.chat_id || '';
  const messageId = message.message_id || '';
  const senderId = (sender.sender_id || {}).open_id || '';

  // Parse content JSON
  let text = '';
  try {
    const contentObj = JSON.parse(message.content || '{}');
    text = contentObj.text || '';
  } catch (e) {
    text = message.content || '';
  }

  // Resolve agent_id from routing table
  const routing = routingConfig || {};
  const toAgent = routing[chatId] || chatId;
  const fromAgent = routing[senderId] || senderId;

  // Deterministic thread_id: sha256 of chat_id, first 8 hex chars
  const threadId = crypto.createHash('sha256').update(chatId).digest('hex').slice(0, 8);

  // Subject: first 30 chars of text
  const subject = text.slice(0, 30);

  return {
    from: fromAgent,
    to: toAgent,
    subject,
    body: text,
    intent: 'SAY',
    thread_id: threadId,
    platform_ref: {
      platform: 'feishu',
      chat_id: chatId,
      message_id: messageId,
      sender_id: senderId,
      reply_token: messageId,
    },
  };
}

/**
 * Get or refresh Feishu app_access_token (cached, refreshed every 2h).
 *
 * @param {object} config - {app_id, app_secret}
 * @returns {Promise<string>} token
 */
function _getToken(config) {
  return new Promise((resolve, reject) => {
    const now = Date.now();
    if (_tokenCache && now < _tokenExpireAt) {
      return resolve(_tokenCache);
    }

    const body = JSON.stringify({
      app_id: config.app_id,
      app_secret: config.app_secret,
    });

    const req = https.request({
      hostname: 'open.feishu.cn',
      path: '/open-apis/auth/v3/app_access_token/internal',
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'Content-Length': Buffer.byteLength(body),
      },
    }, (res) => {
      let data = '';
      res.on('data', (chunk) => { data += chunk; });
      res.on('end', () => {
        try {
          const parsed = JSON.parse(data);
          if (parsed.code !== 0) {
            return reject(new Error(`Feishu token error: ${parsed.msg}`));
          }
          _tokenCache = parsed.app_access_token;
          // expire 2 minutes before actual expiry
          _tokenExpireAt = Date.now() + (parsed.expire - 120) * 1000;
          resolve(_tokenCache);
        } catch (e) {
          reject(e);
        }
      });
    });
    req.on('error', reject);
    req.write(body);
    req.end();
  });
}

/**
 * Send an outgoing message via Feishu API.
 *
 * @param {object} outMsg - {to_chat_id, text, reply_token}
 * @param {object} config - platform config
 * @returns {Promise<object>} API response
 */
function send(outMsg, config) {
  return _getToken(config).then((token) => {
    return new Promise((resolve, reject) => {
      let path, body;

      if (outMsg.reply_token) {
        // Reply mode
        path = `/open-apis/im/v1/messages/${outMsg.reply_token}/reply`;
        body = JSON.stringify({
          content: JSON.stringify({ text: outMsg.text }),
          msg_type: 'text',
        });
      } else {
        // Send new message
        path = '/open-apis/im/v1/messages?receive_id_type=chat_id';
        body = JSON.stringify({
          receive_id: outMsg.to_chat_id,
          content: JSON.stringify({ text: outMsg.text }),
          msg_type: 'text',
        });
      }

      const req = https.request({
        hostname: 'open.feishu.cn',
        path,
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'Authorization': `Bearer ${token}`,
          'Content-Length': Buffer.byteLength(body),
        },
      }, (res) => {
        let data = '';
        res.on('data', (chunk) => { data += chunk; });
        res.on('end', () => {
          try { resolve(JSON.parse(data)); } catch (e) { resolve({ raw: data }); }
        });
      });
      req.on('error', reject);
      req.write(body);
      req.end();
    });
  });
}

module.exports = { verify, handleSpecial, normalize, send };
