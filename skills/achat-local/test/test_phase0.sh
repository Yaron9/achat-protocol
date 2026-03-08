#!/bin/bash
# Phase 0 通信链路测试
# 测试：achat_pm → metame 发一条消息，验证文件正确写入
set -e

INBOX_DIR=~/.metame/memory/inbox
SKILL_DIR=~/AGI/AChat-worktree-step1/skills/achat-local

echo "=== Phase 0 Test: inbox_send ==="

# 1. 发消息
node "$SKILL_DIR/bin/inbox_send" \
  metame achat_pm "Phase0-Test" "这是自动化测试消息，请忽略"

# 2. 验证文件存在（push 模型下消息可能已被 daemon 自动注入并归档到 read/）
FILE=$(ls -t "$INBOX_DIR/metame/"*.md 2>/dev/null | head -1)
if [ -z "$FILE" ]; then
  # 可能已被 push 模型归档，检查 read/ 目录最新文件
  FILE=$(ls -t "$INBOX_DIR/metame/read/"*.md 2>/dev/null | head -1)
  [ -z "$FILE" ] && echo "FAIL: 消息文件未创建" && exit 1
  echo "PASS: 消息文件已创建（push 模型已自动归档）→ $FILE"
else
  echo "PASS: 消息文件已创建 → $FILE"
fi

# 3. 验证格式
grep -q "FROM: achat_pm" "$FILE" || { echo "FAIL: FROM 字段缺失"; exit 1; }
grep -q "THREAD_ID:" "$FILE" || { echo "FAIL: THREAD_ID 字段缺失"; exit 1; }
grep -q "PSC_LEVEL: 0" "$FILE" || { echo "FAIL: PSC_LEVEL 字段缺失"; exit 1; }
grep -q "TO: metame" "$FILE" || { echo "FAIL: TO 字段缺失"; exit 1; }
grep -q "SUBJECT: Phase0-Test" "$FILE" || { echo "FAIL: SUBJECT 字段缺失"; exit 1; }
echo "PASS: 消息格式验证通过（FROM/TO/SUBJECT/THREAD_ID/PSC_LEVEL）"

# 4. 验证 inbox_read（检查未读或历史）
UNREAD=$(node "$SKILL_DIR/bin/inbox_read" metame --all)
echo "$UNREAD" | grep -q "Phase0-Test" || { echo "FAIL: inbox_read 未读到消息"; exit 1; }
echo "PASS: inbox_read 读取正常"

# 5. 验证 --all 参数不报错
node "$SKILL_DIR/bin/inbox_read" metame --all > /dev/null
echo "PASS: inbox_read --all 执行正常"

echo ""
echo "=== Step 1 Test: x-achat header 验证 ==="

# 6. 验证默认 intent=SAY 已写入
grep -q "X-ACHAT-INTENT: SAY" "$FILE" || { echo "FAIL: X-ACHAT-INTENT 字段缺失或值不为 SAY"; exit 1; }
grep -q "X-ACHAT-VISIBILITY: private" "$FILE" || { echo "FAIL: X-ACHAT-VISIBILITY 字段缺失"; exit 1; }
grep -q "X-ACHAT-VERSION: 0.1.0" "$FILE" || { echo "FAIL: X-ACHAT-VERSION 字段缺失"; exit 1; }
echo "PASS: x-achat 默认字段验证通过（INTENT=SAY / VISIBILITY=private / VERSION=0.1.0）"

# 7. 验证 intent=ASK 参数正确写入
node "$SKILL_DIR/bin/inbox_send" \
  metame achat_pm "Step1-ASK-Test" "这是 ASK intent 测试消息" ASK

ASK_FILE=$(ls -t "$INBOX_DIR/metame/"*.md 2>/dev/null | head -1)
if [ -z "$ASK_FILE" ]; then
  ASK_FILE=$(ls -t "$INBOX_DIR/metame/read/"*.md 2>/dev/null | head -1)
fi
grep -q "X-ACHAT-INTENT: ASK" "$ASK_FILE" || { echo "FAIL: intent=ASK 未正确写入"; exit 1; }
echo "PASS: intent=ASK 参数正确写入"

# 8. 验证旧格式文件（无 x-achat 字段）inbox_read 仍能正常读取
LEGACY_FILE=$(mktemp "$INBOX_DIR/metame/legacy-test-XXXXXX.md")
cat > "$LEGACY_FILE" << 'LEGACY'
FROM: legacy_agent
TO: metame
TS: 2026-01-01T00:00:00.000Z
SUBJECT: LegacyTest
THREAD_ID: legacy-thread-id
PSC_LEVEL: 0

这是旧格式消息，无 x-achat 字段
LEGACY
LEGACY_READ=$(node "$SKILL_DIR/bin/inbox_read" metame --all)
echo "$LEGACY_READ" | grep -q "LegacyTest" || { echo "FAIL: 旧格式消息无法被 inbox_read 读取"; rm -f "$LEGACY_FILE"; exit 1; }
rm -f "$LEGACY_FILE"
echo "PASS: 旧格式文件（无 x-achat 字段）向下兼容验证通过"

echo ""
echo "=== Phase 0 + Step 1 所有测试通过 ✅ ==="
