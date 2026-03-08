#!/bin/bash
set -e
echo "=== Step 6 Test: Thread 持久化协议（A2A 兼容格式）==="

SKILL_DIR=~/AGI/AChat-worktree-step6/skills/achat-local
AGENT_ID=achat_pm

# ── 1. thread_create 创建 ───────────────────────────────────────────
CREATE_OUTPUT=$(node "$SKILL_DIR/bin/thread_create" "测试主题" achat_pm metame)
echo "$CREATE_OUTPUT" | grep -q "THREAD_ID:" || { echo "FAIL: thread_create 未输出 THREAD_ID"; exit 1; }
THREAD_ID=$(echo "$CREATE_OUTPUT" | grep "^THREAD_ID:" | sed 's/^THREAD_ID: //')
echo "  THREAD_ID=$THREAD_ID"
[ -f ~/.metame/memory/threads/"$THREAD_ID".jsonl ] || { echo "FAIL: thread 文件未创建"; exit 1; }
# Verify header JSON
HEAD_TYPE=$(node -e "const l=require('fs').readFileSync(process.env.HOME+'/.metame/memory/threads/$THREAD_ID.jsonl','utf8').trim().split('\n')[0]; console.log(JSON.parse(l).type)")
[ "$HEAD_TYPE" = "thread_header" ] || { echo "FAIL: header type 不是 thread_header (got $HEAD_TYPE)"; exit 1; }
echo "PASS: thread_create 创建"

# ── 2. thread_append 追加 ──────────────────────────────────────────
APPEND_OUTPUT=$(node "$SKILL_DIR/bin/thread_append" "$THREAD_ID" achat_pm metame "你好，这是第一条消息")
echo "$APPEND_OUTPUT" | grep -q "APPENDED seq=1" || { echo "FAIL: thread_append 未输出 APPENDED seq=1 (got: $APPEND_OUTPUT)"; exit 1; }
echo "PASS: thread_append 追加 (seq=1)"

# ── 3. thread_read 输出 ────────────────────────────────────────────
READ_OUTPUT=$(node "$SKILL_DIR/bin/thread_read" "$THREAD_ID")
echo "$READ_OUTPUT" | grep -q "Thread: $THREAD_ID" || { echo "FAIL: thread_read 未包含 thread_id"; exit 1; }
echo "$READ_OUTPUT" | grep -q "你好，这是第一条消息" || { echo "FAIL: thread_read 未包含消息内容"; exit 1; }
echo "$READ_OUTPUT" | grep -q "\[1\] achat_pm → metame" || { echo "FAIL: thread_read 格式不正确"; exit 1; }
echo "PASS: thread_read 输出"

# ── 4. inbox_send 自动同步 thread ─────────────────────────────────
# Use a fresh thread_id via thread_create
CREATE2=$(node "$SKILL_DIR/bin/thread_create" "inbox同步测试" achat_pm metame)
THREAD_ID2=$(echo "$CREATE2" | grep "^THREAD_ID:" | sed 's/^THREAD_ID: //')
echo "  THREAD_ID2=$THREAD_ID2"

# inbox_send doesn't accept thread_id externally — it generates its own uuid
# So we test auto-implicit-create: send without pre-existing thread (inbox_send creates it)
SEND_OUTPUT=$(node "$SKILL_DIR/bin/inbox_send" metame achat_pm "自动同步测试" "inbox自动同步消息体" 2>&1 || true)
echo "$SEND_OUTPUT" | grep -q "Thread synced" || { echo "FAIL: inbox_send 未同步到 thread (output: $SEND_OUTPUT)"; exit 1; }
# Find the thread file created by the latest inbox_send (its thread_id is in the output)
SYNC_THREAD=$(echo "$SEND_OUTPUT" | grep "Thread synced" | sed 's|.*threads/||' | sed 's|\.jsonl.*||')
[ -f ~/.metame/memory/threads/"$SYNC_THREAD".jsonl ] || { echo "FAIL: inbox_send 创建的 thread 文件不存在"; exit 1; }
echo "PASS: inbox_send 自动同步 thread"

# ── 5. 多轮追加 seq 正确 ───────────────────────────────────────────
APPEND2=$(node "$SKILL_DIR/bin/thread_append" "$THREAD_ID" metame achat_pm "第二条消息" SAY)
echo "$APPEND2" | grep -q "APPENDED seq=2" || { echo "FAIL: 第二条消息 seq 不是 2 (got: $APPEND2)"; exit 1; }

APPEND3=$(node "$SKILL_DIR/bin/thread_append" "$THREAD_ID" achat_pm metame "第三条消息" ASK)
echo "$APPEND3" | grep -q "APPENDED seq=3" || { echo "FAIL: 第三条消息 seq 不是 3 (got: $APPEND3)"; exit 1; }

# Verify via thread_read --json
JSON_OUT=$(node "$SKILL_DIR/bin/thread_read" "$THREAD_ID" --json)
SEQ3=$(echo "$JSON_OUT" | tail -1 | node -e "let d=''; process.stdin.on('data',c=>d+=c); process.stdin.on('end',()=>console.log(JSON.parse(d).seq))")
[ "$SEQ3" = "3" ] || { echo "FAIL: 最后一条消息 seq 不是 3 (got: $SEQ3)"; exit 1; }
echo "PASS: 多轮追加 seq 正确 (seq 1→2→3)"

echo ""
echo "=== Step 6 所有测试通过 ✅ ==="
