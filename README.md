# AChat Protocol

> Agent-to-agent signed communication over any platform.

AChat 是一个 Claude Code Skill，任何 agent 装载后即可与其他 AChat agent 进行**有签名、有身份、持久化多轮**的通信——无需改变现有工作流。

## 特性

- **Ed25519 签名**：每条消息签名，防伪造防篡改
- **DID 身份**：`did:key` 全球唯一身份，跨平台不变
- **Thread 持久化**：多轮对话历史，A2A 兼容格式
- **授权白名单**：`authorized_senders` 控制谁可以给你发消息
- **Platform Bridge**：飞书 / 企业微信 webhook，Mac ↔ Windows 跨机通信
- **跨平台**：Mac / Linux / Windows（Node.js 18+）

## 安装

```bash
git clone https://github.com/Yaron9/achat-protocol.git
cd achat-protocol/skills/achat-local

# 链接到 Claude Code skills 目录（自动加载）
ln -sf $(pwd) ~/.claude/skills/achat-local
```

## 快速开始

```bash
SKILL=~/achat-protocol/skills/achat-local

# 1. 生成密钥对 + DID
node $SKILL/bin/keygen my_agent

# 2. 初始化 Capability Card
node $SKILL/bin/capability_card_init my_agent

# 3. 发一条消息
node $SKILL/bin/inbox_send other_agent my_agent "Hello" "第一条 AChat 消息"

# 4. 读消息
node $SKILL/bin/inbox_read other_agent

# 5. 创建多轮对话
THREAD=$(node $SKILL/bin/thread_create "讨论协议设计" my_agent other_agent | grep THREAD_ID | awk '{print $2}')
node $SKILL/bin/thread_append $THREAD my_agent other_agent "你好，我们来讨论一下"
node $SKILL/bin/thread_read $THREAD
```

## Platform Bridge（跨机通信）

复制配置模板：

```bash
cp skills/achat-local/config/bridge.example.yaml ~/.metame/agents/my_agent/bridge.yaml
# 填入飞书 app_id / app_secret / verification_token
```

启动 Bridge 服务：

```bash
node skills/achat-local/bin/bridge_server --config ~/.metame/agents/my_agent/bridge.yaml
```

在飞书开放平台配置 Webhook URL：`http://your-server:9988/webhook/feishu`

## Mac ↔ Windows

两台机器各自：
1. 克隆此仓库，安装 skill
2. 配置同一个飞书 bot 的 `app_id` / `app_secret`
3. `routing` 表里各自填自己负责的 `chat_id → agent_id`
4. 各自启动 `bridge_server`

消息经飞书中继，Ed25519 签名端到端验证。

## 命令速查

| 命令 | 说明 |
|------|------|
| `bin/keygen [agent_id]` | 生成 Ed25519 密钥对 + DID |
| `bin/inbox_send <to> <from> <subject> <body> [intent]` | 发消息 |
| `bin/inbox_read <agent_id>` | 读未读消息 |
| `bin/verify_message <file>` | 验证签名 |
| `bin/authorize add <agent_id>` | 加白名单 |
| `bin/thread_create [subject]` | 创建 Thread |
| `bin/thread_append <id> <from> <to> <text>` | 追加消息 |
| `bin/thread_read <id>` | 读 Thread |
| `bin/bridge_server --config <yaml>` | 启动 Platform Bridge |
| `bin/bridge_send <platform> <chat_id> <text>` | 通过平台发消息 |

Intent 类型：`SAY`（默认）`ASK` `PROPOSE` `DECIDE` `DELEGATE` `UPDATE` `BLOCK`

## 运行测试

```bash
cd skills/achat-local
bash test/run_all.sh
```

## 依赖

- Node.js >= 18
- js-yaml（`npm install -g js-yaml`）

## License

MIT
