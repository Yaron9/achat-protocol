#!/bin/bash
set -e
echo "=== Step 3 Test: Ed25519 签名 ==="

SKILL_DIR=~/AGI/AChat-worktree-step3/skills/achat-local

# 1. 生成密钥对
node "$SKILL_DIR/bin/keygen" achat_pm
echo "PASS: 密钥对生成"

# 2. 幂等性
node "$SKILL_DIR/bin/keygen" achat_pm
KEY_COUNT=$(ls ~/.metame/agents/achat_pm/key.json 2>/dev/null | wc -l)
[ "$KEY_COUNT" -eq 1 ] || { echo "FAIL: 密钥重复生成"; exit 1; }
echo "PASS: keygen 幂等性"

# 3. 发一条签名消息
node "$SKILL_DIR/bin/inbox_send" metame achat_pm "SignTest" "签名测试消息"
FILE=$(ls -t ~/.metame/memory/inbox/metame/read/*.md 2>/dev/null | head -1)
grep -q "SIGNATURE:" "$FILE" || { echo "FAIL: 签名字段缺失"; exit 1; }
echo "PASS: 消息包含签名"

# 4. 验证签名有效
RESULT=$(node "$SKILL_DIR/bin/verify_message" "$FILE")
echo "$RESULT" | grep -q "VALID" || { echo "FAIL: 签名验证失败 — $RESULT"; exit 1; }
echo "PASS: 签名验证通过"

# 5. 篡改后验证失败
TAMPERED=$(mktemp /tmp/tampered_XXXX.md)
cat "$FILE" | sed 's/签名测试消息/TAMPERED/' > "$TAMPERED"
RESULT2=$(node "$SKILL_DIR/bin/verify_message" "$TAMPERED" 2>/dev/null || true)
echo "$RESULT2" | grep -q "INVALID" || { echo "FAIL: 篡改消息未被检测"; exit 1; }
echo "PASS: 篡改检测正常"
rm "$TAMPERED"

echo ""
echo "=== Step 3 所有测试通过 ✅ ==="
