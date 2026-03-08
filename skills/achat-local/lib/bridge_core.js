'use strict';

const path = require('path');
const os = require('os');
const { execFileSync } = require('child_process');

// Deduplication store: "platform:message_id" -> timestamp (ms)
const seen = new Map();
const DEDUP_TTL_MS = 5 * 60 * 1000; // 5 minutes

/**
 * Check if a message has already been seen (deduplication).
 * Evicts expired entries on each call.
 *
 * @param {string} platform - platform name (e.g. "feishu")
 * @param {string} messageId - platform message ID
 * @returns {boolean} true if duplicate
 */
function isDuplicate(platform, messageId) {
  // Evict expired
  const now = Date.now();
  for (const [key, ts] of seen.entries()) {
    if (now - ts > DEDUP_TTL_MS) seen.delete(key);
  }

  const key = `${platform}:${messageId}`;
  if (seen.has(key)) return true;
  seen.set(key, now);
  return false;
}

/**
 * Resolve the destination agent_id from a chat_id using routing config.
 *
 * @param {string} chatId - platform chat identifier
 * @param {object} config - full bridge config
 * @returns {string} agent_id or chatId if not found
 */
function resolveAgent(chatId, config) {
  const routing = (config && config.routing) || {};
  return routing[chatId] || chatId;
}

/**
 * Resolve outbound routing for a NormalizedAchatMessage.
 * (Placeholder for future outbound routing logic.)
 *
 * @param {object} normalized - NormalizedAchatMessage
 * @returns {object} outgoing message descriptor
 */
function resolveOutbound(normalized) {
  return {
    to: normalized.to,
    from: normalized.from,
    text: normalized.body,
    platform: normalized.platform_ref && normalized.platform_ref.platform,
    chat_id: normalized.platform_ref && normalized.platform_ref.chat_id,
    reply_token: normalized.platform_ref && normalized.platform_ref.reply_token,
  };
}

/**
 * Main routing function: takes a NormalizedAchatMessage and delivers it to
 * the recipient's inbox via inbox_send.
 *
 * @param {object} normalized - NormalizedAchatMessage
 * @param {object} config - full bridge config
 * @returns {object} result {ok: boolean, path?: string, error?: string}
 */
function route(normalized, config) {
  const { from, to, subject, body, intent, thread_id, platform_ref } = normalized;

  // Skip dedup check here (caller may do it before calling route)
  // Write to inbox using inbox_send binary
  const inboxSendBin = path.join(__dirname, '..', 'bin', 'inbox_send');

  try {
    // inbox_send: <to> <from> <subject> <body> [intent]
    const result = execFileSync(
      process.execPath,
      [inboxSendBin, to, from, subject || body.slice(0, 30), body, intent || 'SAY'],
      {
        encoding: 'utf8',
        timeout: 10000,
        env: {
          ...process.env,
          // Disable dispatch notification in bridge context to avoid loops
          ACHAT_NO_DISPATCH: '1',
        },
      }
    );
    return { ok: true, output: result };
  } catch (err) {
    // Exit code 2 = pending (unauthorized sender), treat as non-fatal
    if (err.status === 2) {
      return { ok: false, pending: true, error: err.stderr || err.message };
    }
    return { ok: false, error: err.stderr || err.message };
  }
}

module.exports = { isDuplicate, resolveAgent, resolveOutbound, route, _seen: seen };
