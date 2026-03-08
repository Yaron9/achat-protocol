'use strict';

const crypto = require('crypto');
const https = require('https');

// Module-level token cache
let _tokenCache = null;
let _tokenExpireAt = 0;

/**
 * Verify webhook signature from 企业微信 (WeCom/WeChat Work).
 * Signature = SHA1(sort([token, timestamp, nonce]).join(''))
 *
 * @param {object} opts
 * @param {object} opts.headers - HTTP headers
 * @param {Buffer|string} opts.rawBody - raw request body
 * @param {object} opts.body - parsed body (XML decoded or object)
 * @param {object} opts.query - URL query params (msg_signature, timestamp, nonce)
 * @param {object} config - platform config (token)
 * @returns {boolean}
 */
function verify({ headers, rawBody, body, query }, config) {
  const token = config.token || '';
  if (!token) return true;

  const msgSignature = (query && query.msg_signature) || '';
  const timestamp = (query && query.timestamp) || '';
  const nonce = (query && query.nonce) || '';

  // Sort and join
  const arr = [token, timestamp, nonce].sort();
  const expected = crypto.createHash('sha1').update(arr.join('')).digest('hex');

  return expected === msgSignature;
}

/**
 * Handle special WeCom events (URL verification / echostr).
 * GET requests contain echostr for URL verification.
 *
 * @param {object} opts
 * @param {object} opts.body - parsed body
 * @param {object} opts.query - URL query params
 * @param {object} opts.method - HTTP method string
 * @param {object} opts.res - HTTP response object
 * @param {object} config - platform config
 * @returns {boolean} true if handled
 */
function handleSpecial({ body, query, method, res }, config) {
  if (method === 'GET') {
    // URL verification: return echostr
    const echostr = (query && query.echostr) || '';
    res.writeHead(200, { 'Content-Type': 'text/plain' });
    res.end(echostr);
    return true;
  }
  return false;
}

/**
 * Simple XML field extractor (no external dependencies).
 * Extracts value of a single XML tag.
 *
 * @param {string} xml
 * @param {string} tag
 * @returns {string}
 */
function _extractXmlField(xml, tag) {
  const match = xml.match(new RegExp(`<${tag}><!\\[CDATA\\[([^\\]]*?)\\]\\]></${tag}>|<${tag}>([^<]*)</${tag}>`));
  if (!match) return '';
  return (match[1] !== undefined ? match[1] : match[2]) || '';
}

/**
 * Normalize a WeCom event payload into NormalizedAchatMessage.
 *
 * WeCom XML fields: ToUserName, FromUserName, Content, MsgId, MsgType
 *
 * @param {string|object} payload - raw XML string or pre-parsed object
 * @param {object} config - platform config
 * @param {object} routingConfig - routing table {chat_id -> agent_id}
 * @returns {object} NormalizedAchatMessage
 */
function normalize(payload, config, routingConfig) {
  let toUser, fromUser, content, msgId, msgType;

  if (typeof payload === 'string') {
    // Parse XML
    toUser = _extractXmlField(payload, 'ToUserName');
    fromUser = _extractXmlField(payload, 'FromUserName');
    content = _extractXmlField(payload, 'Content');
    msgId = _extractXmlField(payload, 'MsgId');
    msgType = _extractXmlField(payload, 'MsgType');
  } else {
    // Already parsed object
    toUser = payload.ToUserName || '';
    fromUser = payload.FromUserName || '';
    content = payload.Content || '';
    msgId = payload.MsgId || '';
    msgType = payload.MsgType || '';
  }

  const routing = routingConfig || {};
  const toAgent = routing[toUser] || toUser;
  const fromAgent = routing[fromUser] || fromUser;

  // Deterministic thread_id based on fromUser+toUser combination
  const chatKey = [fromUser, toUser].sort().join(':');
  const threadId = crypto.createHash('sha256').update(chatKey).digest('hex').slice(0, 8);

  const subject = content.slice(0, 30);

  return {
    from: fromAgent,
    to: toAgent,
    subject,
    body: content,
    intent: 'SAY',
    thread_id: threadId,
    platform_ref: {
      platform: 'wechat_work',
      chat_id: toUser,
      message_id: msgId,
      sender_id: fromUser,
      reply_token: fromUser,
      msg_type: msgType,
    },
  };
}

/**
 * Get or refresh WeCom access_token (cached, 7200s - 120s buffer).
 *
 * @param {object} config - {corp_id, corp_secret}
 * @returns {Promise<string>} token
 */
function _getToken(config) {
  return new Promise((resolve, reject) => {
    const now = Date.now();
    if (_tokenCache && now < _tokenExpireAt) {
      return resolve(_tokenCache);
    }

    const path = `/cgi-bin/gettoken?corpid=${config.corp_id}&corpsecret=${config.corp_secret}`;
    const req = https.request({
      hostname: 'qyapi.weixin.qq.com',
      path,
      method: 'GET',
    }, (res) => {
      let data = '';
      res.on('data', (chunk) => { data += chunk; });
      res.on('end', () => {
        try {
          const parsed = JSON.parse(data);
          if (parsed.errcode !== 0) {
            return reject(new Error(`WeCom token error: ${parsed.errmsg}`));
          }
          _tokenCache = parsed.access_token;
          _tokenExpireAt = Date.now() + (parsed.expires_in - 120) * 1000;
          resolve(_tokenCache);
        } catch (e) {
          reject(e);
        }
      });
    });
    req.on('error', reject);
    req.end();
  });
}

/**
 * Send a message via WeCom API.
 *
 * @param {object} outMsg - {to_user, text, agent_id_ww}
 * @param {object} config - platform config
 * @returns {Promise<object>} API response
 */
function send(outMsg, config) {
  return _getToken(config).then((token) => {
    return new Promise((resolve, reject) => {
      const bodyObj = {
        touser: outMsg.to_user || '@all',
        msgtype: 'text',
        agentid: config.agent_id_ww,
        text: { content: outMsg.text },
      };
      const body = JSON.stringify(bodyObj);

      const req = https.request({
        hostname: 'qyapi.weixin.qq.com',
        path: `/cgi-bin/message/send?access_token=${token}`,
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
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
