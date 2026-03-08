#!/usr/bin/env bash
set -euo pipefail

PASS=0
FAIL=0
SKILL_DIR="$(cd "$(dirname "$0")/.." && pwd)"
TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT

pass() { echo "PASS: $1"; PASS=$((PASS + 1)); }
fail() { echo "FAIL: $1"; FAIL=$((FAIL + 1)); }

run_node() {
  local script="$1"
  local tmpfile="$TMP_DIR/node_$PASS$FAIL.js"
  printf '%s' "$script" > "$tmpfile"
  # Capture stdout only; stderr goes to /dev/null to avoid noise from deps
  node "$tmpfile" 2>/dev/null
  rm -f "$tmpfile"
}

# ─────────────────────────────────────────────────────────────
# Test 1: feishu.verify PASS - valid HMAC-SHA256 + current timestamp
# ─────────────────────────────────────────────────────────────
result=$(run_node "
'use strict';
const crypto = require('crypto');
const feishu = require('$SKILL_DIR/lib/adapters/feishu.js');

const token = 'test_token_123';
const timestamp = String(Math.floor(Date.now() / 1000));
const nonce = 'abc123';
const body = '{\"type\":\"event\"}';

const payload = timestamp + nonce + body;
const signature = crypto.createHmac('sha256', token).update(payload).digest('hex');

const config = { verification_token: token };
const headers = {
  'x-lark-request-timestamp': timestamp,
  'x-lark-request-nonce': nonce,
  'x-lark-signature': signature,
};

const ok = feishu.verify({ headers, rawBody: body, body: JSON.parse(body) }, config);
console.log(ok ? 'true' : 'false');
process.exit(0);
")

if [ "$result" = "true" ]; then
  pass "feishu.verify PASS (valid signature + current timestamp)"
else
  fail "feishu.verify PASS (got: $result)"
fi

# ─────────────────────────────────────────────────────────────
# Test 2: feishu.verify FAIL (tampered body)
# ─────────────────────────────────────────────────────────────
result=$(run_node "
'use strict';
const crypto = require('crypto');
const feishu = require('$SKILL_DIR/lib/adapters/feishu.js');

const token = 'test_token_123';
const timestamp = String(Math.floor(Date.now() / 1000));
const nonce = 'abc123';
const originalBody = '{\"type\":\"event\"}';
const tamperedBody = '{\"type\":\"HACKED\"}';

const payload = timestamp + nonce + originalBody;
const signature = crypto.createHmac('sha256', token).update(payload).digest('hex');

const config = { verification_token: token };
const headers = {
  'x-lark-request-timestamp': timestamp,
  'x-lark-request-nonce': nonce,
  'x-lark-signature': signature,
};

const ok = feishu.verify({ headers, rawBody: tamperedBody, body: JSON.parse(tamperedBody) }, config);
console.log(ok ? 'true' : 'false');
process.exit(0);
")

if [ "$result" = "false" ]; then
  pass "feishu.verify FAIL (tampered body correctly rejected)"
else
  fail "feishu.verify FAIL (should have been false, got: $result)"
fi

# ─────────────────────────────────────────────────────────────
# Test 3: feishu.verify FAIL (replay - old timestamp)
# ─────────────────────────────────────────────────────────────
result=$(run_node "
'use strict';
const crypto = require('crypto');
const feishu = require('$SKILL_DIR/lib/adapters/feishu.js');

const token = 'test_token_123';
const timestamp = String(Math.floor(Date.now() / 1000) - 600);
const nonce = 'abc123';
const body = '{\"type\":\"event\"}';

const payload = timestamp + nonce + body;
const signature = crypto.createHmac('sha256', token).update(payload).digest('hex');

const config = { verification_token: token };
const headers = {
  'x-lark-request-timestamp': timestamp,
  'x-lark-request-nonce': nonce,
  'x-lark-signature': signature,
};

const ok = feishu.verify({ headers, rawBody: body, body: JSON.parse(body) }, config);
console.log(ok ? 'true' : 'false');
process.exit(0);
")

if [ "$result" = "false" ]; then
  pass "feishu.verify FAIL (replay attack - old timestamp correctly rejected)"
else
  fail "feishu.verify FAIL (should have been false for old timestamp, got: $result)"
fi

# ─────────────────────────────────────────────────────────────
# Test 4: feishu.handleSpecial - URL verification challenge
# ─────────────────────────────────────────────────────────────
result=$(run_node "
'use strict';
const feishu = require('$SKILL_DIR/lib/adapters/feishu.js');

let responseData = null;
let statusCode = null;
const mockRes = {
  writeHead(code) { statusCode = code; },
  end(data) { responseData = data; },
};

const body = { type: 'url_verification', challenge: 'test123' };
const handled = feishu.handleSpecial({ body, query: {}, res: mockRes });

if (handled && responseData) {
  const parsed = JSON.parse(responseData);
  console.log(parsed.challenge);
} else {
  console.log('NOT_HANDLED');
}
process.exit(0);
")

if [ "$result" = "test123" ]; then
  pass "feishu.handleSpecial challenge (returned correct challenge)"
else
  fail "feishu.handleSpecial challenge (got: $result)"
fi

# ─────────────────────────────────────────────────────────────
# Test 5: feishu.normalize - correct field extraction
# ─────────────────────────────────────────────────────────────
result=$(run_node "
'use strict';
const feishu = require('$SKILL_DIR/lib/adapters/feishu.js');

const payload = {
  event: {
    message: {
      chat_id: 'oc_test_chat_001',
      message_id: 'om_test_msg_001',
      content: JSON.stringify({ text: 'Hello AChat from Feishu!' }),
    },
    sender: {
      sender_id: {
        open_id: 'ou_test_sender_001',
      },
    },
  },
};

const config = { app_id: 'cli_xxx' };
const routing = { 'oc_test_chat_001': 'achat_pm' };
const normalized = feishu.normalize(payload, config, routing);

const ok =
  normalized.body === 'Hello AChat from Feishu!' &&
  normalized.to === 'achat_pm' &&
  normalized.platform_ref.chat_id === 'oc_test_chat_001' &&
  normalized.platform_ref.platform === 'feishu' &&
  normalized.platform_ref.message_id === 'om_test_msg_001' &&
  normalized.thread_id.length === 8;

console.log(ok ? 'true' : JSON.stringify(normalized));
process.exit(0);
")

if [ "$result" = "true" ]; then
  pass "feishu.normalize correctly extracts fields"
else
  fail "feishu.normalize (got: $result)"
fi

# ─────────────────────────────────────────────────────────────
# Test 6: bridge_core.isDuplicate - deduplication
# ─────────────────────────────────────────────────────────────
result=$(run_node "
'use strict';
const core = require('$SKILL_DIR/lib/bridge_core.js');

const platform = 'feishu';
const msgId = 'om_dedup_test_' + Date.now();

const first = core.isDuplicate(platform, msgId);
const second = core.isDuplicate(platform, msgId);

console.log(!first && second ? 'true' : 'false');
process.exit(0);
")

if [ "$result" = "true" ]; then
  pass "bridge_core.isDuplicate correctly deduplicates"
else
  fail "bridge_core.isDuplicate (got: $result)"
fi

# ─────────────────────────────────────────────────────────────
# Test 7: bridge_core.route - writes to inbox
# ─────────────────────────────────────────────────────────────
TEST_AGENT="bridge_test_agent_$$"
METAME_DIR="$HOME/.metame"
INBOX_DIR="$METAME_DIR/memory/inbox/$TEST_AGENT"
mkdir -p "$INBOX_DIR"

result=$(run_node "
'use strict';
const fs = require('fs');
const path = require('path');
const os = require('os');
const core = require('$SKILL_DIR/lib/bridge_core.js');

const normalized = {
  from: 'feishu_user_001',
  to: '$TEST_AGENT',
  subject: 'Test message',
  body: 'Hello from bridge_core.route test',
  intent: 'SAY',
  thread_id: 'deadbeef',
  platform_ref: {
    platform: 'feishu',
    chat_id: 'oc_test',
    message_id: 'om_route_test_001',
    sender_id: 'ou_test',
    reply_token: 'om_route_test_001',
  },
};

const config = {
  agent_id: '$TEST_AGENT',
  routing: { oc_test: '$TEST_AGENT' },
  platforms: {},
};

const routeResult = core.route(normalized, config);

// Check inbox directory exists and route succeeded
// (a background daemon may move .md files to read/ immediately, so we check output)
const inboxDir = path.join(os.homedir(), '.metame', 'memory', 'inbox', '$TEST_AGENT');
const inboxExists = fs.existsSync(inboxDir);

// Check output mentions 'Message written' (confirms file was written)
const output = routeResult.output || '';
const written = output.includes('Message written');

const ok = routeResult.ok && inboxExists && written;
console.log(ok ? 'true' : JSON.stringify({ok: routeResult.ok, inboxExists, written, error: routeResult.error}));
process.exit(0);
")

rm -rf "$INBOX_DIR" 2>/dev/null || true

if [ "$result" = "true" ]; then
  pass "bridge_core.route writes message to inbox"
else
  fail "bridge_core.route (got: $result)"
fi

# ─────────────────────────────────────────────────────────────
# Test 8: wechat_work.verify PASS - SHA1 signature
# ─────────────────────────────────────────────────────────────
result=$(run_node "
'use strict';
const crypto = require('crypto');
const ww = require('$SKILL_DIR/lib/adapters/wechat_work.js');

const token = 'ww_test_token';
const timestamp = String(Math.floor(Date.now() / 1000));
const nonce = 'xyz789';

const arr = [token, timestamp, nonce].sort();
const msgSignature = crypto.createHash('sha1').update(arr.join('')).digest('hex');

const config = { token };
const query = { msg_signature: msgSignature, timestamp, nonce };

const ok = ww.verify({ headers: {}, rawBody: '', body: {}, query }, config);
console.log(ok ? 'true' : 'false');
process.exit(0);
")

if [ "$result" = "true" ]; then
  pass "wechat_work.verify PASS (SHA1 signature correct)"
else
  fail "wechat_work.verify PASS (got: $result)"
fi

# ─────────────────────────────────────────────────────────────
# Test 9: bridge_send command exists and is executable
# ─────────────────────────────────────────────────────────────
BRIDGE_SEND="$SKILL_DIR/bin/bridge_send"
if [ -f "$BRIDGE_SEND" ] && [ -x "$BRIDGE_SEND" ]; then
  pass "bridge_send exists and is executable"
else
  fail "bridge_send missing or not executable (path: $BRIDGE_SEND)"
fi

# ─────────────────────────────────────────────────────────────
# Test 10: bridge.example.yaml exists and is valid YAML
# ─────────────────────────────────────────────────────────────
YAML_FILE="$SKILL_DIR/config/bridge.example.yaml"
if [ -f "$YAML_FILE" ]; then
  parse_result=$(run_node "
'use strict';
const yaml = require('/Users/yaron/node_modules/js-yaml');
const fs = require('fs');
try {
  const obj = yaml.load(fs.readFileSync('$YAML_FILE', 'utf8'));
  const ok = obj && obj.port && obj.agent_id && obj.platforms && obj.routing;
  console.log(ok ? 'true' : 'false');
} catch(e) {
  console.log('ERROR: ' + e.message);
}
process.exit(0);
")
  if [ "$parse_result" = "true" ]; then
    pass "bridge.example.yaml exists and is valid YAML"
  else
    fail "bridge.example.yaml invalid (got: $parse_result)"
  fi
else
  fail "bridge.example.yaml not found at $YAML_FILE"
fi

# ─────────────────────────────────────────────────────────────
# Summary
# ─────────────────────────────────────────────────────────────
echo ""
echo "Results: $PASS passed, $FAIL failed"
echo ""

if [ "$FAIL" -eq 0 ]; then
  echo "=== Step 8 所有测试通过 ✅ ==="
  exit 0
else
  echo "=== Step 8 测试未全部通过 ❌ (${FAIL} failed) ==="
  exit 1
fi
