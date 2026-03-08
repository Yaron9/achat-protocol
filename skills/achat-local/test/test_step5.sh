#!/bin/bash
set -e
echo "=== Step 5 Test: DID did:key 生成 ==="

SKILL_DIR=~/AGI/AChat-worktree-step5/skills/achat-local
AGENT_ID=achat_pm

# 1. did_gen 生成 DID
DID_OUTPUT=$(node "$SKILL_DIR/bin/did_gen" "$AGENT_ID")
echo "$DID_OUTPUT" | grep -q "DID: did:key:z" || { echo "FAIL: did_gen 未输出 DID"; exit 1; }
echo "PASS: did_gen 生成 DID"

# 2. DID 格式验证 — 以 "did:key:z" 开头，长度 > 40
DID=$(echo "$DID_OUTPUT" | grep "^DID:" | sed 's/^DID: //')
echo "  DID = $DID"
[[ "$DID" == did:key:z* ]] || { echo "FAIL: DID 不以 did:key:z 开头"; exit 1; }
[ ${#DID} -gt 40 ] || { echo "FAIL: DID 长度不足 40 (got ${#DID})"; exit 1; }
echo "PASS: DID 格式验证"

# 3. did_gen 幂等 — 再次运行输出相同 DID
DID_OUTPUT2=$(node "$SKILL_DIR/bin/did_gen" "$AGENT_ID")
DID2=$(echo "$DID_OUTPUT2" | grep "^DID:" | sed 's/^DID: //')
[ "$DID" = "$DID2" ] || { echo "FAIL: did_gen 幂等失败 ($DID != $DID2)"; exit 1; }
echo "PASS: did_gen 幂等"

# 4. keygen 后 agent.yaml.did 自动填充
# First ensure keygen writes DID (key already exists, but DID should be refreshed)
node "$SKILL_DIR/bin/keygen" "$AGENT_ID"
YAML_DID=$(grep "^did:" ~/.metame/agents/"$AGENT_ID"/agent.yaml | sed 's/^did: //')
[[ "$YAML_DID" == did:key:z* ]] || { echo "FAIL: keygen 后 agent.yaml.did 未填充 (got '$YAML_DID')"; exit 1; }
echo "PASS: keygen 后 agent.yaml.did 自动填充"

# 5. inbox_send 消息头包含 X-ACHAT-FROM-DID
node "$SKILL_DIR/bin/inbox_send" metame "$AGENT_ID" "DIDTest" "DID 头部测试消息" 2>/dev/null || true
FILE=$(ls -t ~/.metame/memory/inbox/metame/*.md 2>/dev/null | head -1)
if [ -z "$FILE" ]; then
  # Try read subdirectory as well
  FILE=$(ls -t ~/.metame/memory/inbox/metame/read/*.md 2>/dev/null | head -1)
fi
[ -n "$FILE" ] || { echo "FAIL: 未找到发送的消息文件"; exit 1; }
grep -q "X-ACHAT-FROM-DID: did:key:z" "$FILE" || { echo "FAIL: 消息头缺少 X-ACHAT-FROM-DID (file: $FILE)"; exit 1; }
echo "PASS: inbox_send 消息头包含 X-ACHAT-FROM-DID"

echo ""
echo "=== Step 5 所有测试通过 ✅ ==="
