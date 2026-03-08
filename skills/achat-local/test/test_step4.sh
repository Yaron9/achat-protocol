#!/bin/bash
set -e
echo "=== Step 4 Test: 授权白名单 + pending 隔离 ==="

SKILL_DIR=~/AGI/AChat-worktree-step4/skills/achat-local
AUTHORIZE="$SKILL_DIR/bin/authorize"
INBOX_SEND="$SKILL_DIR/bin/inbox_send"

TARGET_AGENT="test_target_step4"
TARGET_YAML=~/.metame/agents/${TARGET_AGENT}/agent.yaml

# Setup: create a fresh test target agent
mkdir -p ~/.metame/agents/${TARGET_AGENT}
cat > "$TARGET_YAML" <<'YAML'
id: test_target_step4
name: Test Target Agent
authorized_senders: []
YAML

echo ""
echo "--- Test 1: 空白名单允许任意发送 ---"
# authorized_senders is [], so any sender should be allowed
ACHAT_AGENT_ID=${TARGET_AGENT} node "$AUTHORIZE" list ${TARGET_AGENT}
# Send from an arbitrary sender - should succeed (exit 0)
node "$INBOX_SEND" ${TARGET_AGENT} anyone_agent "Test1" "open inbox test"
# Verify message landed in inbox (not pending) — daemon may move to read/ subdir
MSG=$(ls -t ~/.metame/memory/inbox/${TARGET_AGENT}/*.md ~/.metame/memory/inbox/${TARGET_AGENT}/read/*.md 2>/dev/null | head -1)
[ -n "$MSG" ] || { echo "FAIL: 消息未写入 inbox"; exit 1; }
grep -q "FROM: anyone_agent" "$MSG" || { echo "FAIL: FROM 字段不对"; exit 1; }
echo "PASS: 空白名单允许任意发送"

echo ""
echo "--- Test 2: 白名单存在，from 在内 → 发送成功 ---"
# Reset authorized_senders and add achat_pm
cat > "$TARGET_YAML" <<'YAML'
id: test_target_step4
name: Test Target Agent
authorized_senders: []
YAML
ACHAT_AGENT_ID=${TARGET_AGENT} node "$AUTHORIZE" add achat_pm
# Verify it was added
ACHAT_AGENT_ID=${TARGET_AGENT} node "$AUTHORIZE" list ${TARGET_AGENT} | grep -q "achat_pm" || { echo "FAIL: achat_pm 未加入白名单"; exit 1; }
# Send from achat_pm - should succeed
node "$INBOX_SEND" ${TARGET_AGENT} achat_pm "Test2" "authorized sender test"
MSG2=$(ls -t ~/.metame/memory/inbox/${TARGET_AGENT}/*.md ~/.metame/memory/inbox/${TARGET_AGENT}/read/*.md 2>/dev/null | head -1)
[ -n "$MSG2" ] || { echo "FAIL: 授权发送者消息未写入 inbox"; exit 1; }
grep -q "FROM: achat_pm" "$MSG2" || { echo "FAIL: FROM 字段不对"; exit 1; }
echo "PASS: 白名单中的发送者发送成功"

echo ""
echo "--- Test 3: 白名单存在，from 不在内 → 退出码 2，消息在 pending/ ---"
# Clear pending dir before test
rm -rf ~/.metame/memory/inbox/${TARGET_AGENT}/pending/
# Send from stranger_agent - should fail with exit code 2
set +e
node "$INBOX_SEND" ${TARGET_AGENT} stranger_agent "Test3" "unauthorized sender test"
EXIT_CODE=$?
set -e
[ "$EXIT_CODE" -eq 2 ] || { echo "FAIL: 期望退出码 2，实际 $EXIT_CODE"; exit 1; }
# Verify message is in pending/
PENDING_MSG=$(ls ~/.metame/memory/inbox/${TARGET_AGENT}/pending/*.md 2>/dev/null | head -1)
[ -n "$PENDING_MSG" ] || { echo "FAIL: 消息未写入 pending/"; exit 1; }
grep -q "FROM: stranger_agent" "$PENDING_MSG" || { echo "FAIL: pending 消息 FROM 字段不对"; exit 1; }
grep -q "X-ACHAT-STATUS: pending" "$PENDING_MSG" || { echo "FAIL: pending 消息缺少 STATUS 字段"; exit 1; }
echo "PASS: 未授权发送者 → 退出码 2，消息在 pending/"

echo ""
echo "--- Test 4: authorize list 正常输出 ---"
# achat_pm should be in the list
OUTPUT=$(ACHAT_AGENT_ID=${TARGET_AGENT} node "$AUTHORIZE" list ${TARGET_AGENT})
echo "$OUTPUT" | grep -q "achat_pm" || { echo "FAIL: list 输出不包含 achat_pm"; exit 1; }
echo "PASS: authorize list 正常输出"

echo ""
echo "--- Test 5: authorize remove 幂等 ---"
# Remove achat_pm
ACHAT_AGENT_ID=${TARGET_AGENT} node "$AUTHORIZE" remove achat_pm
# Remove again - should not error (idempotent)
ACHAT_AGENT_ID=${TARGET_AGENT} node "$AUTHORIZE" remove achat_pm
# Verify list is now empty
OUTPUT2=$(ACHAT_AGENT_ID=${TARGET_AGENT} node "$AUTHORIZE" list ${TARGET_AGENT})
echo "$OUTPUT2" | grep -q "open to all" || { echo "FAIL: remove 后白名单应为空"; exit 1; }
echo "PASS: authorize remove 幂等"

echo ""
echo "--- Cleanup ---"
rm -rf ~/.metame/agents/${TARGET_AGENT}
rm -rf ~/.metame/memory/inbox/${TARGET_AGENT}
echo "清理完成"

echo ""
echo "=== Step 4 所有测试通过 ✅ ==="
