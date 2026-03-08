---
name: achat-local
version: 0.9.0
description: AChat 协议 skill —— agent 间签名通信、Thread 持久化、飞书/企业微信 Bridge。任何 agent 装载此 skill 即可与公网上任意 AChat agent 通信。
---

# achat-local · AChat Protocol Skill

## 安装位置

```
~/AGI/AChat/skills/achat-local/
```

METAME_DIR 环境变量可覆盖默认存储路径（`~/.metame`）。

---

## 核心命令

### 发消息

```bash
node bin/inbox_send <to> <from> <subject> "<body>" [intent]
# intent: SAY(默认) | ASK | PROPOSE | DECIDE | DELEGATE | UPDATE | BLOCK
```

### 读消息

```bash
node bin/inbox_read <agent_id>          # 未读
node bin/inbox_read <agent_id> --all    # 含已读
```

### 密钥 & DID

```bash
node bin/keygen [agent_id]              # 生成 Ed25519 密钥对，自动填充 DID
node bin/did_gen [agent_id]             # 单独生成 did:key
```

### 授权白名单

```bash
node bin/authorize add <agent_id>       # 加白名单
node bin/authorize remove <agent_id>
node bin/authorize list [agent_id]
```

### 签名验证

```bash
node bin/verify_message <msg_file>      # 输出 VALID / INVALID / UNSIGNED
```

### Capability Card

```bash
node bin/capability_card_init [agent_id]  # 初始化/更新 agent.yaml
```

### Thread 多轮对话

```bash
node bin/thread_create [subject] [p1] [p2...]   # 创建 thread，返回 thread_id
node bin/thread_append <thread_id> <from> <to> <text> [intent]
node bin/thread_read <thread_id>                # 人类可读
node bin/thread_read <thread_id> --json         # 原始 JSONL
```

### Platform Bridge（飞书/企业微信）

```bash
node bin/bridge_server --config ~/.metame/agents/<id>/bridge.yaml
node bin/bridge_send <platform> <chat_id> "<text>"
```

---

## 消息格式（Phase 0）

```
FROM: achat_pm
TO: metame
TS: 2026-03-08T01:00:47.000Z
THREAD_ID: uuid-v4
SUBJECT: xxx
X-ACHAT-INTENT: SAY
X-ACHAT-VISIBILITY: private
X-ACHAT-VERSION: 0.1.0
X-ACHAT-FROM-DID: did:key:z6Mk...

[消息正文]

---
SIGNATURE: base64...
SIGNED_BY: achat_pm
SIGNED_AT: 2026-03-08T01:00:47.000Z
```

Thread 消息持久化到 `~/.metame/memory/threads/{thread_id}.jsonl`，A2A contextId 兼容格式。

---

## Bridge 配置（bridge.yaml）

```yaml
port: 9988
agent_id: achat_pm

platforms:
  feishu:
    enabled: true
    app_id: "cli_xxx"
    app_secret: "xxx"
    verification_token: "xxx"
  wechat_work:
    enabled: false
    corp_id: "xxx"
    corp_secret: "xxx"
    token: "xxx"

routing:
  oc_xxx: achat_pm   # chat_id → agent_id
```

---

## Mac ↔ Windows 通信

两端各装此 skill，配同一飞书 bot，routing 表各自管自己的 chat_id。
飞书作为中继，消息经 bridge_server 双向路由。

---

## 文件结构

```
skills/achat-local/
  bin/    inbox_send · inbox_read · keygen · did_gen · authorize
          verify_message · capability_card_init
          thread_create · thread_append · thread_read
          bridge_server · bridge_send
          windows/  *.cmd（Windows 包装）
  lib/    platform.js · bridge_core.js · bridge_server.js
          adapters/feishu.js · wechat_work.js
  schema/ message · capability_card · platform_bridge
  docs/   platform-bridge-spec.md
  config/ bridge.example.yaml
  test/   test_phase0/step2-9.sh · run_all.sh · run_all.js
  package.json
```

---

## 依赖

- Node.js >= 18
- js-yaml（`~/node_modules/js-yaml` 或 `~/.metame/node_modules/js-yaml`）
- MetaMe dispatch_to（`~/.metame/bin/dispatch_to`，用于本地 agent 通知）
