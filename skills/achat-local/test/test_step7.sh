#!/bin/bash
set -e
echo "=== Step 7 Test: Platform Bridge 接口定义与参考实现 ==="

SKILL_DIR=~/AGI/AChat-worktree-step7/skills/achat-local
BRIDGE_STUB="$SKILL_DIR/bin/bridge_stub"
SCHEMA="$SKILL_DIR/schema/platform_bridge.schema.json"
SPEC="$SKILL_DIR/docs/platform-bridge-spec.md"
TMP_DIR=$(mktemp -d)

cleanup() {
  rm -rf "$TMP_DIR"
  # Clean up test inbox if created
  rm -rf ~/.metame/memory/inbox/test_bridge_target_step7 2>/dev/null || true
  rm -rf ~/.metame/agents/test_bridge_sender_step7 2>/dev/null || true
  rm -rf ~/.metame/agents/test_bridge_target_step7 2>/dev/null || true
}
trap cleanup EXIT

echo ""
echo "--- Test 1: schema 文件存在且是合法 JSON ---"
[ -f "$SCHEMA" ] || { echo "FAIL: schema 文件不存在: $SCHEMA"; exit 1; }
node -e "JSON.parse(require('fs').readFileSync('$SCHEMA', 'utf8'))" || { echo "FAIL: schema 文件不是合法 JSON"; exit 1; }
# Verify key definitions exist in schema
node -e "
  const s = JSON.parse(require('fs').readFileSync('$SCHEMA', 'utf8'));
  const defs = s.definitions;
  const required = ['IncomingMessage', 'OutgoingMessage', 'BridgeAdapter', 'NormalizedAchatMessage'];
  for (const k of required) {
    if (!defs[k]) throw new Error('Missing definition: ' + k);
  }
" || { echo "FAIL: schema 缺少必要 definitions"; exit 1; }
echo "PASS: schema 文件存在且是合法 JSON，包含所有必要 definitions"

echo ""
echo "--- Test 2: bridge_stub capabilities 输出合法 JSON ---"
[ -f "$BRIDGE_STUB" ] || { echo "FAIL: bridge_stub 不存在"; exit 1; }
[ -x "$BRIDGE_STUB" ] || { echo "FAIL: bridge_stub 不可执行"; exit 1; }
CAPS=$(node "$BRIDGE_STUB" capabilities)
echo "$CAPS" | node -e "
  const data = JSON.parse(require('fs').readFileSync('/dev/stdin', 'utf8'));
  if (!data.name) throw new Error('Missing name');
  if (!data.platform) throw new Error('Missing platform');
  if (!Array.isArray(data.capabilities)) throw new Error('capabilities must be array');
  if (!data.capabilities.includes('normalize')) throw new Error('must include normalize capability');
  if (!data.capabilities.includes('send')) throw new Error('must include send capability');
  if (!data.auth_type) throw new Error('Missing auth_type');
" || { echo "FAIL: capabilities 输出不合法"; exit 1; }
echo "PASS: bridge_stub capabilities 输出合法 JSON"

echo ""
echo "--- Test 3: bridge_stub normalize 正确映射字段 ---"
cat > "$TMP_DIR/incoming.json" <<'JSON'
{
  "platform": "wechat",
  "chat_id": "gh_test_001",
  "sender_id": "wx_user_12345",
  "sender_name": "测试用户",
  "text": "你好，这是一条测试消息",
  "ts": "2026-03-08T10:00:00.000Z",
  "achat_from": "test_wechat_agent",
  "achat_to": "achat_pm"
}
JSON

NORMALIZED=$(node "$BRIDGE_STUB" normalize "$TMP_DIR/incoming.json")
echo "$NORMALIZED" | node -e "
  const data = JSON.parse(require('fs').readFileSync('/dev/stdin', 'utf8'));
  if (!data.from) throw new Error('Missing from');
  if (!data.to) throw new Error('Missing to');
  if (!data.body) throw new Error('Missing body');
  if (!data.thread_id) throw new Error('Missing thread_id');
  if (!data.intent) throw new Error('Missing intent');
  if (!data.subject) throw new Error('Missing subject');
  if (data.from !== 'test_wechat_agent') throw new Error('from should be test_wechat_agent, got: ' + data.from);
  if (data.to !== 'achat_pm') throw new Error('to should be achat_pm, got: ' + data.to);
  if (data.body !== '你好，这是一条测试消息') throw new Error('body mismatch: ' + data.body);
  if (!data.platform_ref) throw new Error('Missing platform_ref');
  if (data.platform_ref.platform !== 'wechat') throw new Error('platform_ref.platform should be wechat');
  if (data.platform_ref.sender_id !== 'wx_user_12345') throw new Error('platform_ref.sender_id mismatch');
  console.log('  from=' + data.from + ', to=' + data.to + ', intent=' + data.intent);
" || { echo "FAIL: normalize 字段映射不正确"; exit 1; }

# Test intent parsing from text prefix
cat > "$TMP_DIR/incoming_ask.json" <<'JSON'
{
  "platform": "feishu",
  "chat_id": "oc_test_002",
  "sender_id": "feishu_user_001",
  "text": "/ask 这个功能如何实现？",
  "ts": "2026-03-08T10:01:00.000Z",
  "achat_from": "feishu_agent",
  "achat_to": "achat_pm"
}
JSON
NORM_ASK=$(node "$BRIDGE_STUB" normalize "$TMP_DIR/incoming_ask.json")
echo "$NORM_ASK" | node -e "
  const data = JSON.parse(require('fs').readFileSync('/dev/stdin', 'utf8'));
  if (data.intent !== 'ASK') throw new Error('intent should be ASK, got: ' + data.intent);
  console.log('  intent parsed correctly: ' + data.intent);
" || { echo "FAIL: normalize 未正确解析 intent 前缀"; exit 1; }

echo "PASS: bridge_stub normalize 正确映射字段（含 from/to/body/platform_ref/intent）"

echo ""
echo "--- Test 4: docs/platform-bridge-spec.md 存在 ---"
[ -f "$SPEC" ] || { echo "FAIL: platform-bridge-spec.md 不存在: $SPEC"; exit 1; }
# Check key sections exist
grep -q "normalize" "$SPEC" || { echo "FAIL: spec 缺少 normalize 接口说明"; exit 1; }
grep -q "send" "$SPEC" || { echo "FAIL: spec 缺少 send 接口说明"; exit 1; }
grep -q "getCapabilities" "$SPEC" || { echo "FAIL: spec 缺少 getCapabilities 接口说明"; exit 1; }
grep -q "authorized_senders" "$SPEC" || { echo "FAIL: spec 缺少安全要求说明"; exit 1; }
LINE_COUNT=$(wc -l < "$SPEC")
echo "  spec 文件行数: $LINE_COUNT"
[ "$LINE_COUNT" -gt 50 ] || { echo "FAIL: spec 文件太短 ($LINE_COUNT 行)"; exit 1; }
echo "PASS: docs/platform-bridge-spec.md 存在且包含所有必要章节"

echo ""
echo "--- Test 5: bridge_stub send 成功调用 inbox_send ---"
# Setup test agents
mkdir -p ~/.metame/agents/test_bridge_sender_step7
cat > ~/.metame/agents/test_bridge_sender_step7/agent.yaml <<'YAML'
id: test_bridge_sender_step7
name: Test Bridge Sender
authorized_senders: []
achat:
  version: "0.1.0"
YAML

mkdir -p ~/.metame/agents/test_bridge_target_step7
cat > ~/.metame/agents/test_bridge_target_step7/agent.yaml <<'YAML'
id: test_bridge_target_step7
name: Test Bridge Target
authorized_senders: []
achat:
  version: "0.1.0"
YAML

# Create a NormalizedAchatMessage to send
cat > "$TMP_DIR/outgoing.json" <<'JSON'
{
  "from": "test_bridge_sender_step7",
  "to": "test_bridge_target_step7",
  "subject": "Step7 Bridge Test Message",
  "body": "Hello from Platform Bridge stub test",
  "intent": "SAY",
  "thread_id": "11111111-2222-3333-4444-555555555555",
  "platform_ref": {
    "platform": "wechat",
    "chat_id": "gh_test_001",
    "sender_id": "wx_user_12345",
    "message_ts": "2026-03-08T10:00:00.000Z"
  }
}
JSON

set +e
SEND_OUTPUT=$(node "$BRIDGE_STUB" send "$TMP_DIR/outgoing.json" 2>&1)
SEND_EXIT=$?
set -e

# Exit code 0 = success, 2 = pending (both are "sent" scenarios)
if [ "$SEND_EXIT" -ne 0 ] && [ "$SEND_EXIT" -ne 2 ]; then
  echo "FAIL: bridge_stub send 返回错误码 $SEND_EXIT"
  echo "Output: $SEND_OUTPUT"
  exit 1
fi

# Verify SENT appears in output (inbox_send logs the path)
echo "$SEND_OUTPUT" | grep -q "SENT" || { echo "FAIL: send 输出未包含 SENT 确认"; echo "Output: $SEND_OUTPUT"; exit 1; }

# Verify message arrived in inbox, read/, or pending/ (daemon may move to read/ quickly)
INBOX_BASE=~/.metame/memory/inbox/test_bridge_target_step7
INBOX_MSG=$(find "$INBOX_BASE" -name "*.md" 2>/dev/null | head -1)
[ -n "$INBOX_MSG" ] || { echo "FAIL: send 后 inbox 目录未找到消息文件"; exit 1; }
grep -q "FROM: test_bridge_sender_step7" "$INBOX_MSG" || { echo "FAIL: 消息 FROM 字段不对"; exit 1; }
grep -q "Step7 Bridge Test Message" "$INBOX_MSG" || { echo "FAIL: 消息 SUBJECT 字段不对"; exit 1; }
echo "PASS: bridge_stub send 成功调用 inbox_send，消息已写入 inbox"

echo ""
echo "=== Step 7 所有测试通过 ✅ ==="
