#!/bin/bash
set -e
echo "=== Step 2 Test: Capability Card ==="

# 1. 对 achat_pm 执行升级
node ~/AGI/AChat-worktree-step2/skills/achat-local/bin/capability_card_init achat_pm

# 2. 验证字段存在
YAML=~/.metame/agents/achat_pm/agent.yaml
grep -q "contact_policy:" "$YAML" || { echo "FAIL: contact_policy 缺失"; exit 1; }
grep -q "authorized_senders:" "$YAML" || { echo "FAIL: authorized_senders 缺失"; exit 1; }
grep -q "pricing:" "$YAML" || { echo "FAIL: pricing 缺失"; exit 1; }
grep -q "achat:" "$YAML" || { echo "FAIL: achat 缺失"; exit 1; }
echo "PASS: 所有 Capability Card 字段已写入"

# 3. 验证幂等性（再次执行不报错，不重复字段）
node ~/AGI/AChat-worktree-step2/skills/achat-local/bin/capability_card_init achat_pm
COUNT=$(grep -c "contact_policy:" "$YAML")
[ "$COUNT" -eq 1 ] || { echo "FAIL: 字段重复（idempotency 失败）"; exit 1; }
echo "PASS: 幂等性验证通过"

echo ""
echo "=== Step 2 所有测试通过 ✅ ==="
