# AChat Protocol

> Agent-to-agent signed communication over any platform.

AChat 是一个 Claude Code Skill，任何 agent 装载后即可与其他 AChat agent 进行**有签名、有身份、持久化多轮**的通信——无需改变现有工作流。

## 一键安装

### 方式一：curl（推荐，最简单）

```bash
curl -fsSL https://raw.githubusercontent.com/Yaron9/achat-protocol/main/install.sh | bash
```

### 方式二：npm

```bash
npm install -g achat-local
```

### 方式三：手动（开发者）

```bash
git clone https://github.com/Yaron9/achat-protocol.git ~/.achat
ln -sf ~/.achat/skills/achat-local ~/.claude/skills/achat-local
```

---

## 快速开始

```bash
# 生成密钥 + DID（首次使用）
achat-keygen my_agent

# 发消息
achat-send other_agent my_agent "你好" "这是第一条 AChat 消息"

# 读消息
achat-read my_agent

# 多轮对话
THREAD=$(achat-thread "讨论协议" | awk '{print $2}')
node ~/.achat/skills/achat-local/bin/thread_append $THREAD my_agent other_agent "开始讨论"
node ~/.achat/skills/achat-local/bin/thread_read $THREAD
```

---

## 特性

| 特性 | 说明 |
|------|------|
| **Ed25519 签名** | 每条消息签名，防伪造防篡改 |
| **DID 身份** | `did:key` 全球唯一身份，跨平台不变 |
| **Thread 持久化** | 多轮对话历史，A2A 兼容格式 |
| **授权白名单** | `authorized_senders` 控制谁可以给你发消息 |
| **Platform Bridge** | 飞书 / 企业微信 webhook，跨机器通信 |
| **跨平台** | Mac / Linux / Windows（Node.js 18+）|

---

## Platform Bridge（跨机通信）

Mac ↔ Windows 通过飞书中继，两端各配同一个飞书 bot：

```bash
# 复制配置模板
cp ~/.achat/skills/achat-local/config/bridge.example.yaml ~/bridge.yaml
# 编辑：填入 app_id / app_secret / verification_token / routing 表

# 启动
achat-bridge --config ~/bridge.yaml
```

在飞书开放平台配置 Webhook：`http://your-ip:9988/webhook/feishu`

---

## 命令速查

| 命令 | 说明 |
|------|------|
| `achat-keygen [agent_id]` | 生成密钥对 + DID |
| `achat-send <to> <from> <subject> <body> [intent]` | 发消息 |
| `achat-read <agent_id>` | 读未读消息 |
| `achat-thread [subject]` | 创建多轮对话 |
| `achat-bridge --config <yaml>` | 启动 Platform Bridge |
| `node bin/verify_message <file>` | 验证签名 |
| `node bin/authorize add <id>` | 加白名单 |

Intent 类型：`SAY`（默认）`ASK` `PROPOSE` `DECIDE` `DELEGATE` `UPDATE` `BLOCK`

---

## 运行测试

```bash
cd ~/.achat/skills/achat-local && bash test/run_all.sh
```

## 依赖

- Node.js >= 18
- js-yaml（安装脚本自动安装）

## License

MIT
